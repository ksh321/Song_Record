import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as native;

import '../../config/app_config.dart';
import '../domain/identifiers.dart';
import 'account_database.dart' show AccountDatabase;
import 'account_paths.dart';
import 'local_models.dart';

typedef SupportDirectory = Future<Directory> Function();

// Keep isolate callbacks outside manager closures: only the temporary path may
// cross the isolate boundary, never the manager's pending Future queue.
QueryExecutor _openNativeDatabase(File file, String tempPath) =>
    NativeDatabase.createInBackground(
      file,
      isolateSetup: () {
        native.sqlite3.tempDirectory = tempPath;
      },
      setup: _configureSqlite,
    );

void _configureSqlite(native.Database database) {
  database.execute('PRAGMA journal_mode = WAL');
}

/// One instance per app session. Authentication must supply the verified UUID;
/// this storage boundary does not authenticate arbitrary caller-supplied IDs.
final class AccountStoreManager {
  AccountStoreManager({
    required this.environment,
    SupportDirectory? directory,
    SupportDirectory? temporaryDirectory,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final AppEnvironment environment;
  final SupportDirectory _directory;
  final SupportDirectory _temporaryDirectory;
  Future<void> _tail = Future<void>.value();
  AccountStore? _active;
  int _generation = 0;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completion = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completion.complete(await action());
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    });
    return completion.future;
  }

  Future<AccountStore> openAccount(String userId) {
    final canonicalId = UuidValue(userId).value;
    final generation = ++_generation; // Invalidate old handles immediately.
    return _serialize(() async {
      if (generation != _generation) {
        throw StateError('Account opening was superseded');
      }
      final previous = _active;
      _active = null;
      await previous?._database.close();
      final paths = await AccountPaths.create(
        await _directory(),
        canonicalId,
        environment,
      );
      final file = await paths.databaseFile();
      final tempPath = (await _temporaryDirectory()).path;
      final database = AccountDatabase(
        _openNativeDatabase(file, tempPath),
        userId: canonicalId,
        environment: environment,
      );
      try {
        await database.verifyReady();
        if (generation != _generation) {
          throw StateError('Account changed while opening storage');
        }
      } catch (_) {
        await database.close();
        rethrow;
      }
      final store = AccountStore._(this, database, paths, generation);
      _active = store;
      return store;
    });
  }

  Future<void> logout() {
    ++_generation;
    return _serialize(() async {
      final previous = _active;
      _active = null;
      await previous?._database.close();
      // Deliberately preserve the DB, pending edits, journals, and audio files.
    });
  }

  Future<T> _run<T>(
    AccountStore store,
    Future<T> Function() action,
  ) => _serialize(() async {
    void requireCurrent() {
      if (!identical(_active, store) || store._generation != _generation) {
        throw StateError('This account storage session has expired');
      }
    }

    requireCurrent();
    final result = await action();
    requireCurrent(); // Do not deliver a late account-A result to account-B UI.
    return result;
  });
}

/// Scoped lease, not a global database singleton. No raw database or File escapes
/// this API. Login/logout integration belongs to P06; recorder bridging to P18.
final class AccountStore {
  AccountStore._(this._manager, this._database, this._paths, this._generation);
  final AccountStoreManager _manager;
  final AccountDatabase _database;
  final AccountPaths _paths;
  final int _generation;
  String get userId => _paths.userId;

  Future<T> _run<T>(Future<T> Function() action) => _manager._run(this, action);

  Future<MetadataCopy?> readMetadata(
    LocalEntity entity,
    String entityId,
  ) => _run(() async {
    final row = await _database
        .customSelect(
          'SELECT * FROM metadata_copies WHERE entity_type=? AND entity_id=?',
          variables: [
            Variable(entity.code),
            Variable(UuidValue(entityId).value),
          ],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : MetadataCopy(
            revision: row.read<int>('server_revision'),
            serverJson: row.readNullable<String>('server_payload'),
            localJson: row.readNullable<String>('local_payload'),
            tombstone: row.read<int>('tombstone') == 1,
          );
  });

  Future<void> saveEdit(LocalEdit edit) => _run(() async {
    _validatePayloadOwner(edit.draftJson);
    _validatePayloadOwner(edit.changesJson);
    final fingerprint = sha256
        .convert(
          utf8.encode(
            canonicalJson({
              'entity': edit.entity.code,
              'id': edit.entityId,
              'operation': edit.operation.code,
              'base_revision': edit.baseRevision,
              'draft': jsonDecode(edit.draftJson),
              'changes': jsonDecode(edit.changesJson),
            }),
          ),
        )
        .toString();
    await _database.transaction(() async {
      final oldRequest = await _database
          .customSelect(
            'SELECT request_hash FROM local_mutations WHERE op_id=?',
            variables: [Variable(edit.opId)],
          )
          .getSingleOrNull();
      if (oldRequest != null) {
        if (oldRequest.read<String>('request_hash') != fingerprint) {
          throw StateError('An op_id cannot be reused for a different edit');
        }
        return; // A retry must not overwrite a newer local draft.
      }
      final baseline = await _database
          .customSelect(
            'SELECT server_revision,server_payload,tombstone FROM metadata_copies WHERE entity_type=? AND entity_id=?',
            variables: [Variable(edit.entity.code), Variable(edit.entityId)],
          )
          .getSingleOrNull();
      if ((baseline?.read<int>('server_revision') ?? 0) != edit.baseRevision ||
          baseline?.read<int>('tombstone') == 1) {
        throw StateError(
          'Edit baseline changed or the resource was permanently deleted',
        );
      }
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await _database.customStatement(
        '''INSERT INTO metadata_copies(user_id,entity_type,entity_id,local_payload,updated_at)
        VALUES(?,?,?,?,?) ON CONFLICT(entity_type,entity_id) DO UPDATE SET local_payload=excluded.local_payload,updated_at=excluded.updated_at''',
        [userId, edit.entity.code, edit.entityId, edit.draftJson, now],
      );
      await _database.customStatement(
        '''INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,
        base_payload,payload,request_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
        [
          edit.opId,
          userId,
          edit.entity.code,
          edit.entityId,
          edit.operation.code,
          edit.baseRevision,
          baseline?.readNullable<String>('server_payload'),
          edit.changesJson,
          fingerprint,
          now,
          now,
        ],
      );
    });
  });

  void _validatePayloadOwner(String json) {
    final payload = jsonDecode(json) as Map<String, Object?>;
    if (payload.containsKey('user_id') && payload['user_id'] != userId) {
      throw ArgumentError('Payload belongs to another account');
    }
  }

  Future<List<QueuedMutation>> pendingMutations() => _run(() async {
    final rows = await _database
        .customSelect(
          "SELECT * FROM local_mutations WHERE queue_state<>'ACKED' ORDER BY created_at,op_id",
        )
        .get();
    return rows
        .map(
          (row) => QueuedMutation(
            opId: row.read<String>('op_id'),
            state: row.read<String>('queue_state'),
            baseRevision: row.read<int>('base_revision'),
            payload: row.read<String>('payload'),
            basePayload: row.readNullable<String>('base_payload'),
            serverResponse: row.readNullable<String>('server_response'),
            attemptCount: row.read<int>('attempt_count'),
          ),
        )
        .toList(growable: false);
  });

  Future<int?> readCursor() => _run(
    () async =>
        (await _database
                .customSelect(
                  'SELECT last_change_seq FROM sync_cursors WHERE singleton=1',
                )
                .getSingle())
            .readNullable<int>('last_change_seq'),
  );

  Future<void> saveSnapshotResume(Map<String, Object?> resume) {
    final json = canonicalJson(resume);
    return _run(
      () => _database.customStatement(
        'UPDATE sync_cursors SET snapshot_resume=?,updated_at=? WHERE singleton=1',
        [json, DateTime.now().toUtc().millisecondsSinceEpoch],
      ),
    );
  }

  Future<String?> readSnapshotResume() => _run(
    () async =>
        (await _database
                .customSelect(
                  'SELECT snapshot_resume FROM sync_cursors WHERE singleton=1',
                )
                .getSingle())
            .readNullable<String>('snapshot_resume'),
  );

  Future<void> recordFileAndJournal({
    required String recordingId,
    required String operationId,
    required FilePresence state,
    required JournalPhase phase,
    required bool pending,
    String? checksum,
    int? sizeBytes,
    required Map<String, Object?> recovery,
  }) {
    final id = UuidValue(recordingId).value;
    final op = UuidValue(operationId).value;
    final json = canonicalJson(recovery);
    return _run(() async {
      final relative = pending ? _paths.pendingPath(id) : _paths.audioPath(id);
      if (pending &&
          (state == FilePresence.inputPending || state == FilePresence.saved)) {
        throw ArgumentError(
          'Completed recordings must use the final audio path',
        );
      }
      final file = await _paths.checkedFile(relative);
      int? verifiedAt;
      if (state == FilePresence.inputPending || state == FilePresence.saved) {
        if (!await file.exists() ||
            await file.length() != sizeBytes ||
            sizeBytes == null ||
            sizeBytes > 6291456 ||
            sizeBytes < 1) {
          throw StateError(
            'Completed local file is missing or has a different size',
          );
        }
        if ((await sha256.bind(file.openRead()).first).toString() != checksum) {
          throw StateError('Completed local file checksum mismatch');
        }
        verifiedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      }
      await _database.transaction(() async {
        final journal = await _database
            .customSelect(
              'SELECT operation_id FROM recording_journals WHERE recording_id=?',
              variables: [Variable(id)],
            )
            .getSingleOrNull();
        if (journal != null && journal.read<String>('operation_id') != op) {
          throw StateError(
            'A recording journal belongs to its original operation',
          );
        }
        final old = await _database
            .customSelect(
              'SELECT local_state,sha256,size_bytes FROM local_recording_files WHERE recording_id=?',
              variables: [Variable(id)],
            )
            .getSingleOrNull();
        if (old?.read<String>('local_state') == 'SAVED' &&
            (old?.readNullable<String>('sha256') != checksum ||
                old?.readNullable<int>('size_bytes') != sizeBytes)) {
          throw StateError(
            'Do not replace the content of a saved recording UUID',
          );
        }
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        await _database.customStatement(
          '''INSERT INTO local_recording_files(recording_id,user_id,relative_path,sha256,size_bytes,local_state,verified_at,updated_at)
          VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(recording_id) DO UPDATE SET relative_path=excluded.relative_path,sha256=excluded.sha256,
          size_bytes=excluded.size_bytes,local_state=excluded.local_state,verified_at=excluded.verified_at,updated_at=excluded.updated_at''',
          [
            id,
            userId,
            relative,
            checksum,
            sizeBytes,
            state.code,
            verifiedAt,
            now,
          ],
        );
        await _database.customStatement(
          '''INSERT INTO recording_journals(recording_id,user_id,operation_id,pending_path,final_path,phase,recovery_payload,updated_at)
          VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(recording_id) DO UPDATE SET phase=excluded.phase,recovery_payload=excluded.recovery_payload,
          revision=recording_journals.revision+1,updated_at=excluded.updated_at''',
          [
            id,
            userId,
            op,
            _paths.pendingPath(id),
            _paths.audioPath(id),
            phase.code,
            json,
            now,
          ],
        );
      });
    });
  }

  Future<Uint8List> readLocalAudio(String recordingId) => _run(() async {
    final id = UuidValue(recordingId).value;
    final row = await _database
        .customSelect(
          'SELECT relative_path,sha256,size_bytes,local_state FROM local_recording_files WHERE recording_id=?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    if (row == null ||
        !['INPUT_PENDING', 'SAVED'].contains(row.read<String>('local_state'))) {
      throw StateError('There is no verified readable local file');
    }
    final path = row.read<String>('relative_path');
    if (path != _paths.audioPath(id)) {
      throw StateError('Pending files are not playable');
    }
    final file = await _paths.checkedFile(path);
    final size = await file.length();
    if (size < 1 || size > 6291456 || size != row.read<int>('size_bytes')) {
      throw StateError('Local file size changed');
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != row.read<String>('sha256')) {
      throw StateError('Local file checksum changed');
    }
    return bytes;
  });

  Future<String?> readJournal(String recordingId) => _run(
    () async =>
        (await _database
                .customSelect(
                  'SELECT recovery_payload FROM recording_journals WHERE recording_id=?',
                  variables: [Variable(UuidValue(recordingId).value)],
                )
                .getSingleOrNull())
            ?.read<String>('recovery_payload'),
  );

  Future<void> createImportJob({
    required String jobId,
    required String sourceUserId,
    required String manifestHash,
    required List<String> resourceIds,
  }) {
    final id = UuidValue(jobId).value;
    final source = UuidValue(sourceUserId).value;
    final resources = resourceIds
        .map((item) => UuidValue(item).value)
        .toList(growable: false);
    return _run(() async {
      if (source != userId) {
        throw ArgumentError('Backup account does not match the active account');
      }
      await _paths.checkedFile(_paths.importPath(id));
      await _database.transaction(() async {
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        await _database.customStatement(
          'INSERT INTO import_jobs(import_job_id,user_id,source_user_id,archive_path,manifest_hash,total_items,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)',
          [
            id,
            userId,
            source,
            _paths.importPath(id),
            manifestHash,
            resources.length,
            now,
            now,
          ],
        );
        for (var index = 0; index < resources.length; index++) {
          await _database.customStatement(
            'INSERT INTO import_items(import_job_id,ordinal,resource_id,updated_at) VALUES(?,?,?,?)',
            [id, index + 1, resources[index], now],
          );
        }
      });
    });
  }

  Future<List<String>> pendingImportJobs() => _run(
    () async =>
        (await _database
                .customSelect(
                  "SELECT import_job_id FROM import_jobs WHERE status<>'COMPLETED' ORDER BY created_at,import_job_id",
                )
                .get())
            .map((row) => row.read<String>('import_job_id'))
            .toList(growable: false),
  );
}
