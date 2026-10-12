import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../core/database/account_store.dart';
import '../../../core/database/local_models.dart';
import '../../../core/domain/identifiers.dart';
import 'import_conflicts.dart';
import 'import_decision.dart';
import 'import_outcome.dart';
import 'import_preflight.dart';
import 'import_roles.dart';

/// Applies only a reviewed, conflict-free plan. Unknown commands stop BEFORE
/// preparing a journal; server policy/source/history rows are never replayed.
Future<ImportOutcome> applyReviewedImport({
  required AccountStore store,
  required ImportConsent consent,
  required ImportConflictPreview preview,
  required ImportServerBaseline server,
  required File archive,
  required Future<void> Function() synchronize,
  required Future<ImportServerBaseline> Function() refresh,
  required void Function() requireCurrent,
  required int held,
}) async {
  requireCurrent();
  if (preview.requiresChoice) {
    throw StateError('Import requires conflict review');
  }
  final job = consent.source.manifest.exportId;
  final digest = (await sha256.bind(archive.openRead()).first).toString();
  requireCurrent();
  final existing = {
    for (final e in server.entries) '${e.entity}/${e.resourceId}': e.payload,
  };
  final originals = consent.source.data.toJson()['records'] as List;
  final specs = {
    for (final r in originals)
      if (r['entity'] == 'RECORDING_FILE_SPEC')
        r['resource_id']: r['payload'] as Map,
  };
  final items = <Map<String, dynamic>>[];
  final rolePlan = planImportRoles(
    consent: consent,
    preview: preview,
    server: server,
    requireCurrent: requireCurrent,
  );
  final rows = rolePlan.records;
  final newRepresentatives = <String, String>{
    for (final row in rows)
      if (row['entity'] == 'SONG' &&
          !existing.containsKey('SONG/${row["resource_id"]}') &&
          (row['payload'] as Map)['representative_recording_id'] != null)
        row['resource_id'] as String:
            (row['payload'] as Map)['representative_recording_id'] as String,
  };
  const ranks = {
    'TAG': 0,
    'SONG': 1,
    'PLAYLIST': 2,
    'RECORDING': 3,
    'PLAYLIST_ITEM': 4,
  };
  rows.sort(
    (a, b) => (ranks[a['entity']] ?? 5).compareTo(ranks[b['entity']] ?? 5),
  );
  final tails = <String, String>{};
  final lists = <String, List<String>>{};
  final parentDrafts = <String, Map<String, dynamic>>{};
  final prepared = await store.importJobMatches(job, digest);
  if (!prepared) {
    for (final row in rows) {
      requireCurrent();
      final entity = row['entity'] as String, id = row['resource_id'] as String;
      final p = Map<String, dynamic>.from(row['payload'] as Map),
          key = '$entity/$id';
      if (entity == 'RECORDING') {
        final raw = p['file'] ?? specs[id];
        if (raw is Map) {
          p['file'] = {
            for (final f in [
              'sha256',
              'size_bytes',
              'duration_ms',
              'codec',
              'sample_rate',
              'channels',
              'capture_integrity',
            ])
              if (raw.containsKey(f)) f: raw[f],
          };
        }
      }
      final kind = LocalEntity.values
          .where((e) => e.code == entity)
          .firstOrNull;
      final copy = kind == null ? null : await store.readMetadata(kind, id);
      final old = copy?.localJson ?? copy?.serverJson;
      final commands = <Map<String, dynamic>>[];
      String command(
        String operation,
        int revision,
        Map<String, dynamic> draft,
        Map<String, dynamic> changes, {
        String? predecessor,
        String? expected,
      }) {
        final op = UuidValue.random().value;
        commands.add({
          'entity': entity,
          'id': id,
          'op_id': op,
          'operation': operation,
          'base_revision': revision,
          'draft': draft,
          'changes': changes,
          'predecessor': ?predecessor,
          'expected': ?expected,
        });
        tails[key] = op;
        return op;
      }

      Map<String, dynamic> pick(Iterable<String> fields) => {
        for (final f in fields)
          if (p.containsKey(f)) f: p[f],
      };
      if (entity == 'PLAYLIST') parentDrafts[id] = p;
      if (entity == 'PLAYLIST_ITEM' && !existing.containsKey(key)) {
        final parent = p['playlist_id'] as String, song = p['song_id'];
        if (song is! String) {
          throw StateError(
            'Unregistered candidate needs a fresh verified selection',
          );
        }
        final already = server.entries.any(
          (e) =>
              e.entity == 'PLAYLIST_ITEM' &&
              e.payload['playlist_id'] == parent &&
              e.payload['song_id'] == song,
        );
        if (!already) (lists[parent] ??= <String>[]).add(song);
        continue;
      }
      if (entity == 'RECORDING_TAG' && !existing.containsKey(key)) {
        final record = p['recording_id'] as String;
        if (!rows.any(
          (r) => r['entity'] == 'RECORDING' && r['resource_id'] == record,
        )) {
          throw StateError('Missing recording tag parent');
        }
        continue;
      }
      final fields = importEditableFields[entity];
      if (existing.containsKey(key)) {
        if (fields != null) {
          if (copy == null ||
              old == null ||
              copy.revision != existing[key]!['revision']) {
            throw StateError('Receive the current baseline before applying');
          }
          final current = jsonDecode(old) as Map;
          final changed = {
            for (final f in fields)
              if (p.containsKey(f) &&
                  jsonEncode(p[f]) != jsonEncode(current[f]))
                f: p[f],
          };
          // Separate endpoint semantics must not be mixed into a generic PATCH.
          if (changed.containsKey('tier') && entity == 'RECORDING') {
            final tier = changed.remove('tier');
            if (changed.isEmpty) {
              command('PATCH', copy.revision, p, {
                'base_revision': copy.revision,
                'tier': tier,
              }, expected: old);
            } else {
              final before = command('PATCH', copy.revision, p, {
                'base_revision': copy.revision,
                ...changed,
              }, expected: old);
              command('PATCH', 0, p, {
                'base_revision': 0,
                'tier': tier,
              }, predecessor: before);
            }
          } else if (changed.isNotEmpty) {
            command('PATCH', copy.revision, p, {
              'base_revision': copy.revision,
              ...changed,
            }, expected: old);
          }
        }
      } else if (copy != null) {
        // The preview has already proved this unsent local draft is identical.
        // Reuse its original queued operation, including a different export ID.
      } else if (entity == 'SONG' && p['source_type'] == 'MANUAL') {
        if (p['representative_recording_id'] != null &&
            !newRepresentatives.containsKey(id)) {
          throw StateError('New representative selection needs review');
        }
        command('CREATE', 0, p, {
          'id': id,
          ...pick([
            'source_type',
            'title',
            'artist',
            'version_code',
            'tier',
            'note',
          ]),
          'manual_reason': p['manual_reason'] ?? 'TJ_NOT_FOUND',
        });
      } else if (entity == 'PLAYLIST' ||
          entity == 'TAG' && p['archived_at'] == null) {
        command('CREATE', 0, p, {'id': id, 'name': p['name']});
      } else if (entity == 'RECORDING' && p['metadata_state'] == 'SAVED') {
        final spec = p['file'] ?? specs[id];
        if (spec is! Map) {
          throw StateError('Recording file description missing');
        }
        final file = Map<String, dynamic>.from(spec)
          ..remove('recording_id')
          ..remove('created_at');
        p['file'] = file;
        final create = command(
          'CREATE',
          0,
          {...p, 'metadata_state': 'DRAFT'},
          {
            'id': id,
            'metadata_state': 'DRAFT',
            ...pick([
              'song_id',
              'title_snapshot',
              'artist_snapshot',
              'version_code',
              'key_mode',
              'key_shift',
              'note',
              'recorded_at',
              'timezone_id',
              'timezone_offset_minutes',
              'condition_code',
            ]),
          },
        );
        final saved = command('PATCH', 0, p, {
          'base_revision': 0,
          'metadata_state': 'SAVED',
          'file': file,
          ...pick([
            'title_snapshot',
            'artist_snapshot',
            'version_code',
            'key_mode',
            'key_shift',
            'note',
          ]),
        }, predecessor: create);
        var predecessor = saved;
        if (p['tier'] != null) {
          predecessor = command('PATCH', 0, p, {
            'base_revision': 0,
            'tier': p['tier'],
          }, predecessor: saved);
        }
        final tags = <String>{
          ...((p['tag_ids'] as List?) ?? const []).cast<String>(),
          for (final r in originals)
            if (r['entity'] == 'RECORDING_TAG' &&
                r['payload']['recording_id'] == id)
              r['payload']['tag_id'] as String,
        };
        if (tags.isNotEmpty) {
          command('PATCH', 0, p, {
            'base_revision': 0,
            'tag_ids': tags.toList(),
          }, predecessor: predecessor);
        }
      } else if (!{
        'RECORDING_FILE_SPEC',
        'RECORDING_ASSET',
        'SONG_SOURCE',
        'SONG_CLOUD_SELECTION',
        'PIN_SLOT',
        'STORAGE_USAGE',
        'USER_ENTITLEMENT',
        'USER_SYNC_STATE',
        'CHANGE_LOG',
        'DELETION_LEDGER',
        'DELETION_BATCH',
        'DELETION_ITEM',
      }.contains(entity)) {
        throw StateError('This relationship needs a supported import command');
      }
      items.add({
        'resource_id': id,
        'edits': commands,
        'file': entity == 'RECORDING' && preview.fileIds.contains(id)
            ? p['file'] ?? specs[id]
            : null,
      });
    }
    for (final entry in lists.entries) {
      final parent = entry.key,
          current = await store.readMetadata(LocalEntity.playlist, parent);
      final raw = current?.localJson ?? current?.serverJson;
      final draft =
          parentDrafts[parent] ??
          (raw == null ? null : jsonDecode(raw) as Map<String, dynamic>);
      if (draft == null) throw StateError('Missing playlist parent');
      var predecessor = tails['PLAYLIST/$parent'];
      if (predecessor == null && current?.revision == 0) {
        final pending = await store.pendingMutations();
        predecessor = pending
            .where(
              (m) =>
                  m.entity == LocalEntity.playlist &&
                  m.entityId == parent &&
                  m.operation == LocalOperation.create,
            )
            .firstOrNull
            ?.opId;
      }
      final commands = <Map<String, dynamic>>[];
      final ids = entry.value.toSet().toList();
      for (var offset = 0; offset < ids.length; offset += 100) {
        final op = UuidValue.random().value;
        final batch = ids.skip(offset).take(100).toList();
        final revision = predecessor == null ? current?.revision : 0;
        if (revision == null || predecessor == null && revision < 1) {
          throw StateError('Playlist revision unavailable');
        }
        commands.add({
          'entity': 'PLAYLIST',
          'id': parent,
          'op_id': op,
          'operation': 'PATCH',
          'base_revision': revision,
          'draft': draft,
          'changes': {'base_revision': revision, 'song_ids': batch},
          'predecessor': ?predecessor,
          if (predecessor == null)
            'expected': current!.localJson ?? current.serverJson,
        });
        predecessor = op;
      }
      items.add({'resource_id': parent, 'edits': commands, 'file': null});
    }
    for (final entry in newRepresentatives.entries) {
      final parent = entry.key, target = entry.value;
      final predecessor = tails['SONG/$parent'];
      if (predecessor == null) {
        throw StateError('New representative parent unavailable');
      }
      final draft = Map<String, dynamic>.from(
        rows.singleWhere(
              (r) => r['entity'] == 'SONG' && r['resource_id'] == parent,
            )['payload']
            as Map,
      );
      items.add({
        'resource_id': parent,
        'file': null,
        'edits': [
          {
            'entity': 'SONG',
            'id': parent,
            'op_id': UuidValue.random().value,
            'operation': 'PATCH',
            'base_revision': 0,
            'draft': {...draft, 'representative_recording_id': target},
            'predecessor': predecessor,
            'changes': {
              'base_revision': 0,
              'representative_recording_id': target,
            },
          },
        ],
      });
    }
    // No mutation or normal-file copy occurs until every command is representable.
    if (!await store.importJobMatches(job, digest)) {
      await store.prepareImportApply(
        jobId: job,
        manifestHash: digest,
        items: items,
      );
    }
  }
  for (final id in preview.fileIds) {
    requireCurrent();
    final destination = await store.privateExportFile(job, 'audio/$id.m4a');
    final source = consent.source.staging.file('audio/$id.m4a');
    if (!await destination.exists()) await source.copy(destination.path);
    requireCurrent();
  }
  while (await store.applyImportNext(job, requireCurrent)) {
    requireCurrent();
  }
  await synchronize();
  requireCurrent();
  final latest = await refresh();
  requireCurrent();
  final planned = rolePlan.records.map((row) {
    if (row['entity'] != 'PLAYLIST_ITEM') return row;
    final p = row['payload'] as Map;
    final matched = latest.entries
        .where(
          (e) =>
              e.entity == 'PLAYLIST_ITEM' &&
              e.payload['playlist_id'] == p['playlist_id'] &&
              e.payload['song_id'] == p['song_id'],
        )
        .toList();
    return matched.length == 1
        ? {...row, 'resource_id': matched.single.resourceId}
        : row;
  }).toList();
  return readImportOutcome(
    store: store,
    consent: consent,
    jobId: job,
    plannedRecords: planned,
    held: held + rolePlan.heldRepresentatives.length,
    conflicts: 0,
    refreshPolicy: () async => latest,
    requireCurrent: requireCurrent,
  );
}
