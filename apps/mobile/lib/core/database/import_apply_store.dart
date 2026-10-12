part of 'account_store.dart';

/// Immutable account-scoped commands and item results, without file bytes.
extension ImportApplyStore on AccountStore {
  LocalEdit _importEdit(Map<String, dynamic> c) {
    final entity = LocalEntity.values.singleWhere((e) => e.code == c['entity']);
    final operation = LocalOperation.values.singleWhere(
      (e) => e.code == c['operation'],
    );
    if (!{LocalOperation.create, LocalOperation.patch}.contains(operation)) {
      throw const FormatException(
        'Import cannot replay destructive operations',
      );
    }
    final edit = LocalEdit(
      opId: c['op_id'] as String,
      entity: entity,
      entityId: c['id'] as String,
      operation: operation,
      baseRevision: c['base_revision'] as int,
      draft: Map<String, Object?>.from(c['draft'] as Map),
      changes: Map<String, Object?>.from(c['changes'] as Map),
    );
    final changes = jsonDecode(edit.changesJson) as Map<String, dynamic>;
    final followup = c['predecessor'] != null;
    if (followup) {
      UuidValue(c['predecessor'] as String);
      if (operation != LocalOperation.patch || edit.baseRevision != 0) {
        throw const FormatException('Invalid import followup');
      }
      changes['base_revision'] = 1;
    }
    if (MutationRequest.prepare(
          QueuedMutation(
            opId: edit.opId,
            localOrder: 1,
            entity: entity,
            entityId: edit.entityId,
            operation: operation,
            state: 'PENDING',
            baseRevision: followup ? 1 : edit.baseRevision,
            payload: canonicalJson(changes),
            attemptCount: 0,
          ),
        ) ==
        null) {
      throw const FormatException('Unsupported import command');
    }
    _validatePayloadOwner(edit.draftJson);
    return edit;
  }

  Future<void> prepareImportApply({
    required String jobId,
    required String manifestHash,
    required List<Map<String, dynamic>> items,
  }) => _run(() async {
    final job = UuidValue(jobId).value;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(manifestHash) ||
        items.length > 100000) {
      throw const FormatException('Invalid import journal');
    }
    final frozen =
        (jsonDecode(canonicalJson({'items': items}))['items'] as List)
            .cast<Map<String, dynamic>>();
    for (final item in frozen) {
      UuidValue(item['resource_id'] as String);
      final commands = item['edits'] as List;
      for (final command in commands) {
        final edit = _importEdit(command as Map<String, dynamic>);
        if (edit.entityId != item['resource_id']) {
          throw const FormatException('Import target mismatch');
        }
      }
      final file = item['file'];
      if (file != null &&
          (file is! Map ||
              !validRecordingFileSpec(Map<String, dynamic>.from(file)))) {
        throw const FormatException('Invalid import file description');
      }
    }
    await _database.transaction(() async {
      final old = await _database
          .customSelect(
            'SELECT * FROM import_jobs WHERE import_job_id=?',
            variables: [Variable(job)],
          )
          .getSingleOrNull();
      if (old != null) {
        final saved = await _database
            .customSelect(
              'SELECT result_payload FROM import_items WHERE import_job_id=? ORDER BY ordinal',
              variables: [Variable(job)],
            )
            .get();
        final commands = [
          for (final row in saved)
            jsonDecode(row.read<String>('result_payload'))['command'],
        ];
        if (old.read<String>('user_id') != userId ||
            old.read<String>('manifest_hash') != manifestHash ||
            canonicalJson({'items': commands}) !=
                canonicalJson({'items': frozen})) {
          throw StateError('Import job plan changed');
        }
        return;
      }
      final now = _manager._clock().toUtc().millisecondsSinceEpoch;
      await _database.customStatement(
        'INSERT INTO import_jobs(import_job_id,user_id,source_user_id,archive_path,manifest_hash,total_items,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)',
        [
          job,
          userId,
          userId,
          _paths.importPath(job),
          manifestHash,
          frozen.length,
          now,
          now,
        ],
      );
      for (var i = 0; i < frozen.length; i++) {
        await _database.customStatement(
          'INSERT INTO import_items(import_job_id,ordinal,resource_id,result_payload,updated_at) VALUES(?,?,?,?,?)',
          [
            job,
            i + 1,
            frozen[i]['resource_id'],
            canonicalJson({'command': frozen[i], 'file_phase': 'READY'}),
            now,
          ],
        );
      }
    });
  });

  Future<List<Map<String, dynamic>>> importApplyResults(String jobId) =>
      _run(() async {
        final job = UuidValue(jobId).value;
        final owner = await _database
            .customSelect(
              'SELECT user_id FROM import_jobs WHERE import_job_id=?',
              variables: [Variable(job)],
            )
            .getSingle();
        if (owner.read<String>('user_id') != userId) {
          throw StateError('Import owner changed');
        }
        final rows = await _database
            .customSelect(
              'SELECT ordinal,resource_id,status,result_payload FROM import_items WHERE import_job_id=? ORDER BY ordinal',
              variables: [Variable(job)],
            )
            .get();
        return [
          for (final row in rows)
            {
              'ordinal': row.read<int>('ordinal'),
              'resource_id': row.read<String>('resource_id'),
              'status': row.read<String>('status'),
              'result': jsonDecode(row.read<String>('result_payload')),
            },
        ];
      });

  /// One bounded item per call. The caller seals only fresh, approved commands.
  Future<bool> applyImportNext(
    String jobId,
    void Function() requireCurrent, {
    Future<void> Function(String phase)? faultProbe,
  }) => _run(() async {
    requireCurrent();
    final job = UuidValue(jobId).value;
    final header = await _database
        .customSelect(
          'SELECT * FROM import_jobs WHERE import_job_id=?',
          variables: [Variable(job)],
        )
        .getSingle();
    if (header.read<String>('user_id') != userId) {
      throw StateError('Import owner changed');
    }
    final row = await _database
        .customSelect(
          "SELECT * FROM import_items WHERE import_job_id=? AND status='PENDING' ORDER BY ordinal LIMIT 1",
          variables: [Variable(job)],
        )
        .getSingleOrNull();
    if (row == null) {
      await _database.customStatement(
        "UPDATE import_jobs SET status='COMPLETED',completed_items=total_items WHERE import_job_id=?",
        [job],
      );
      return false;
    }
    final ordinal = row.read<int>('ordinal'),
        id = row.read<String>('resource_id');
    final journal =
        jsonDecode(row.read<String>('result_payload')) as Map<String, dynamic>;
    final command = journal['command'] as Map<String, dynamic>;
    try {
      await _database.customStatement(
        "UPDATE import_jobs SET status='RUNNING' WHERE import_job_id=?",
        [job],
      );
      requireCurrent();
      final file = command['file'];
      final targets = <String>{
        if (file != null) 'RECORDING',
        for (final c in command['edits'] as List) c['entity'] as String,
      };
      for (final entity in targets) {
        final deleted = await _database
            .customSelect(
              "SELECT 1 FROM metadata_copies WHERE user_id=? AND entity_type=? AND entity_id=? AND tombstone=1 UNION ALL SELECT 1 FROM snapshot_download_rows p JOIN snapshot_baseline b ON p.snapshot_token=b.snapshot_token AND p.user_id=b.user_id WHERE p.user_id=? AND p.entity='DELETION_LEDGER' AND json_extract(p.canonical_payload,'\$.entity_type')=? AND json_extract(p.canonical_payload,'\$.entity_id')=? LIMIT 1",
              variables: [
                Variable(userId),
                Variable(entity),
                Variable(id),
                Variable(userId),
                Variable(entity),
                Variable(id),
              ],
            )
            .getSingleOrNull();
        if (deleted != null) {
          throw StateError('Import target was permanently deleted');
        }
      }
      if (file != null) {
        final spec = Map<String, dynamic>.from(file as Map);
        final stage = await _paths.exportFile(job, 'audio/$id.m4a');
        if (!await stage.exists() ||
            await stage.length() != spec['size_bytes']) {
          throw StateError('Import staged file missing');
        }
        final bytes = await stage.readAsBytes();
        requireCurrent();
        journal['file_phase'] = 'MOVING';
        await _database.customStatement(
          'UPDATE import_items SET result_payload=? WHERE import_job_id=? AND ordinal=?',
          [canonicalJson(journal), job, ordinal],
        );
        await _preserveDownloadedAudio(
          userId,
          id,
          spec['sha256'] as String,
          spec['size_bytes'] as int,
          bytes,
        );
        journal['file_phase'] = 'VERIFIED';
        await _database.customStatement(
          'UPDATE import_items SET result_payload=? WHERE import_job_id=? AND ordinal=?',
          [canonicalJson(journal), job, ordinal],
        );
        if (faultProbe != null) await faultProbe('FILE_VERIFIED');
      }
      requireCurrent();
      await _database.transaction(() async {
        for (final raw in command['edits'] as List) {
          final c = raw as Map<String, dynamic>, edit = _importEdit(raw);
          await _saveEdit(
            edit,
            expectedEffectivePayload: c['expected'] as String?,
            predecessorOpId: c['predecessor'] as String?,
          );
        }
        requireCurrent();
        journal['file_phase'] = file == null ? 'NOT_REQUIRED' : 'COMMITTED';
        journal.remove('error_code');
        await _database.customStatement(
          "UPDATE import_items SET status='APPLIED',result_payload=? WHERE import_job_id=? AND ordinal=?",
          [canonicalJson(journal), job, ordinal],
        );
        await _database.customStatement(
          'UPDATE import_jobs SET completed_items=completed_items+1 WHERE import_job_id=?',
          [job],
        );
      });
      if (faultProbe != null) await faultProbe('ITEM_COMMITTED');
      return true;
    } catch (_) {
      if (identical(_manager._active, this) &&
          _generation == _manager._generation) {
        journal['error_code'] = 'IMPORT_RECHECK_REQUIRED';
        await _database.customStatement(
          'UPDATE import_items SET result_payload=? WHERE import_job_id=? AND ordinal=?',
          [canonicalJson(journal), job, ordinal],
        );
        await _database.customStatement(
          "UPDATE import_jobs SET status='PAUSED' WHERE import_job_id=?",
          [job],
        );
      }
      rethrow;
    }
  });
}
