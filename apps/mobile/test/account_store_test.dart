import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
// The pinned Drift release wraps background-isolate failures in this type.
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart'
    show AccountDatabase;
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
final userA = id(1), userB = id(2), song = id(10), recording = id(20);
final audio = utf8.encode('synthetic-file-not-real-audio');
final digest = sha256.convert(audio).toString();

Matcher remoteFailure(String message) => throwsA(
  isA<DriftRemoteException>().having(
    (error) => error.toString(),
    'remote cause',
    contains(message),
  ),
);

LocalEdit edit(
  int op, {
  String title = 'draft',
  int base = 0,
  Map<String, Object?>? draft,
}) => LocalEdit(
  opId: id(op),
  entity: LocalEntity.song,
  entityId: song,
  operation: LocalOperation.create,
  baseRevision: base,
  draft: draft ?? {'title': title},
  changes: {'title': title},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  AccountStoreManager makeManager({
    AppEnvironment environment = AppEnvironment.dev,
  }) => AccountStoreManager(
    environment: environment,
    directory: () async => root,
    temporaryDirectory: () async => root,
  );
  Future<AccountPaths> paths(
    String user, {
    AppEnvironment environment = AppEnvironment.dev,
  }) => AccountPaths.create(root, user, environment);
  Future<AccountDatabase> raw(String user) async {
    final file = await (await paths(user)).databaseFile();
    final db = AccountDatabase(
      NativeDatabase(file),
      userId: user,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    return db;
  }

  Future<void> fileFixture(
    AccountStore store, {
    String? recordId,
    int op = 21,
  }) async {
    final rec = recordId ?? recording;
    final location = await paths(store.userId);
    await (await location.checkedFile(location.audioPath(rec)))
        .writeAsBytes(audio, flush: true);
    await store.recordFileAndJournal(
      recordingId: rec,
      operationId: id(op),
      state: FilePresence.saved,
      phase: JournalPhase.committed,
      pending: false,
      checksum: digest,
      sizeBytes: audio.length,
      recovery: {'input': 'preserved', 'native_phase': 'completed'},
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('song_record_p0408_');
    manager = makeManager();
  });
  tearDown(() async {
    await manager.logout();
    // Only delete the unique synthetic test directory created above.
    expect(p.basename(root.path), startsWith('song_record_p0408_'));
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, root.absolute.path),
      isTrue,
    );
    await root.delete(recursive: true);
  });

  test(
    'snapshot request survives restart and rejects stale response writes',
    () async {
      var store = await manager.openAccount(userA);
      final request = {'op_id': id(700), 'phase': 'REQUESTED'};
      expect(
        await store.compareAndSetSnapshotResume(
          expected: null,
          replacement: request,
        ),
        isTrue,
      );
      final saved = await store.readSnapshotResume();
      await manager.logout();
      store = await manager.openAccount(userA);
      expect(await store.readSnapshotResume(), saved);
      expect(
        await store.compareAndSetSnapshotResume(
          expected: null,
          replacement: {'op_id': id(701)},
        ),
        isFalse,
      );
      expect(
        await store.compareAndSetSnapshotResume(
          expected: saved,
          replacement: {...request, 'phase': 'BUILDING'},
        ),
        isTrue,
      );
      final advanced = await store.readSnapshotResume();
      expect(
        await store.compareAndSetSnapshotResume(
          expected: saved,
          replacement: {'op_id': id(701)},
        ),
        isFalse,
      );
      expect(await store.readSnapshotResume(), advanced);
      expect(
        await store.compareAndSetSnapshotResume(
          expected: advanced,
          replacement: null,
        ),
        isTrue,
      );
      expect(
        await store.compareAndSetSnapshotResume(
          expected: advanced,
          replacement: request,
        ),
        isFalse,
      );
      expect(await store.readSnapshotResume(), isNull);
      final other = await manager.openAccount(userB);
      await expectLater(
        store.compareAndSetSnapshotResume(expected: null, replacement: request),
        throwsStateError,
      );
      expect(await other.readSnapshotResume(), isNull);
    },
  );

  test(
    'recovery snapshot retains pending edits and excludes other accounts',
    () async {
      final a = await manager.openAccount(userA);
      await a.saveEdit(edit(100, title: 'private-a'));
      await fileFixture(a);
      final snapshot =
          jsonDecode(await a.recoveryData()) as Map<String, dynamic>;
      expect(snapshot['source_user_id'], userA);
      expect(snapshot['environment'], 'dev');
      final tables = snapshot['tables'] as Map<String, dynamic>;
      expect(tables['local_mutations'], hasLength(1));
      expect(tables['local_recording_files'], hasLength(1));
      expect(snapshot['version'], 2);
      expect(snapshot['schema_version'], 5);

      final exportedFile =
          (tables['local_recording_files'] as List).single
              as Map<String, dynamic>;
      expect(exportedFile['recording_id'], recording);
      expect(exportedFile['user_id'], userA);
      expect(exportedFile['relative_path'], 'audio/$recording.m4a');
      expect(exportedFile['sha256'], digest);
      expect(exportedFile['size_bytes'], audio.length);
      expect(exportedFile['local_state'], 'SAVED');

      final journal =
          (tables['recording_journals'] as List).single as Map<String, dynamic>;
      expect(journal['operation_id'], id(21));
      expect(journal['pending_path'], 'pending/$recording.m4a.part');
      expect(journal['final_path'], 'audio/$recording.m4a');
      expect(journal['phase'], 'COMMITTED');
      expect(jsonDecode(journal['recovery_payload'] as String), {
        'input': 'preserved',
        'native_phase': 'completed',
      });
      expect(await a.readLocalAudio(recording), audio);
      expect(await a.pendingMutations(), hasLength(1));
      final b = await manager.openAccount(userB);
      expect(await b.recoveryData(), isNot(contains('private-a')));
      await expectLater(a.recoveryData(), throwsStateError);
      final restored = await manager.openAccount(userA);
      expect(await restored.recoveryData(), contains('private-a'));
    },
  );

  test('fresh database has unknown cursor, not fabricated zero', () async {
    final a = await manager.openAccount(userA);
    expect(await a.readCursor(), isNull);
    expect(await a.pendingMutations(), isEmpty);
    expect(
      await (await paths(userA)).databaseFile().then((file) => file.exists()),
      isTrue,
    );
  });

  test(
    'edit and mutation survive a new manager and database connection',
    () async {
      var a = await manager.openAccount(userA);
      await a.saveEdit(edit(100));
      await manager.logout();
      manager = makeManager();
      a = await manager.openAccount(userA);
      expect(
        jsonDecode((await a.readMetadata(LocalEntity.song, song))!.localJson!),
        {'title': 'draft'},
      );
      final queued = await a.pendingMutations();
      expect(queued.single.opId, id(100));
      expect(queued.single.baseRevision, 0);
      expect(queued.single.state, 'PENDING');
      expect(queued.single.attemptCount, 0);
    },
  );

  test('idempotent old retry cannot revert a newer draft', () async {
    final a = await manager.openAccount(userA);
    await a.saveEdit(edit(100, title: 'first'));
    await a.saveEdit(edit(101, title: 'second'));
    await a.saveEdit(edit(100, title: 'first'));
    expect(await a.pendingMutations(), hasLength(2));
    expect(
      (await a.readMetadata(LocalEntity.song, song))!.localJson,
      contains('second'),
    );
  });

  test(
    'different edit with reused op id is rejected without overwriting',
    () async {
      final a = await manager.openAccount(userA);
      await a.saveEdit(edit(100));
      await expectLater(
        a.saveEdit(edit(100, title: 'wrong')),
        throwsStateError,
      );
      expect(
        (await a.readMetadata(LocalEntity.song, song))!.localJson,
        contains('draft'),
      );
      expect(await a.pendingMutations(), hasLength(1));
    },
  );

  test(
    'JSON key order and later caller mutation do not change captured edit',
    () async {
      final a = await manager.openAccount(userA);
      final payload = <String, Object?>{
        'z': 1,
        'nested': <String, Object?>{'b': 2, 'a': 1},
      };
      final first = edit(100, draft: payload);
      payload['z'] = 9;
      await a.saveEdit(first);
      await a.saveEdit(
        edit(
          100,
          draft: {
            'nested': {'a': 1, 'b': 2},
            'z': 1,
          },
        ),
      );
      expect(await a.pendingMutations(), hasLength(1));
      expect(
        (await a.readMetadata(LocalEntity.song, song))!.localJson,
        contains('"z":1'),
      );
    },
  );

  test(
    'stale baseline and foreign account payload fail without partial writes',
    () async {
      final a = await manager.openAccount(userA);
      await expectLater(a.saveEdit(edit(100, base: 9)), throwsStateError);
      await expectLater(
        a.saveEdit(edit(101, draft: {'user_id': userB})),
        throwsArgumentError,
      );
      expect(await a.readMetadata(LocalEntity.song, song), isNull);
      expect(await a.pendingMutations(), isEmpty);
    },
  );

  test('database failure rolls metadata and queue back together', () async {
    await manager.openAccount(userA);
    await manager.logout();
    final db = await raw(userA);
    await db.customStatement(
      "CREATE TRIGGER test_queue_failure BEFORE INSERT ON local_mutations BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END",
    );
    await db.close();
    final a = await manager.openAccount(userA);
    await expectLater(
      a.saveEdit(edit(100)),
      remoteFailure('synthetic write failure'),
    );
    expect(await a.readMetadata(LocalEntity.song, song), isNull);
    expect(await a.pendingMutations(), isEmpty);
  });

  test(
    'same resource UUID stays isolated between account databases and files',
    () async {
      final a = await manager.openAccount(userA);
      await a.saveEdit(edit(100, title: 'A'));
      await fileFixture(a);
      final b = await manager.openAccount(userB);
      expect(await b.readMetadata(LocalEntity.song, song), isNull);
      expect(await b.pendingMutations(), isEmpty);
      await expectLater(b.readLocalAudio(recording), throwsStateError);
      await b.saveEdit(edit(100, title: 'B'));
      final reopened = await manager.openAccount(userA);
      expect(
        (await reopened.readMetadata(LocalEntity.song, song))!.localJson,
        contains('A'),
      );
      expect(await reopened.readLocalAudio(recording), audio);
      await expectLater(a.readCursor(), throwsStateError);
      await expectLater(b.readCursor(), throwsStateError);
    },
  );

  test(
    'account switch invalidates queued old-account callbacks immediately',
    () async {
      final a = await manager.openAccount(userA);
      final queued = a.saveEdit(edit(100));
      final rejection = expectLater(queued, throwsStateError);
      final b = await manager.openAccount(userB);
      await rejection;
      expect(await b.pendingMutations(), isEmpty);
      final reopened = await manager.openAccount(userA);
      expect(await reopened.pendingMutations(), isEmpty);
    },
  );

  test(
    'logout preserves audio, journal, import work and snapshot resume',
    () async {
      var a = await manager.openAccount(userA);
      await fileFixture(a);
      await a.createImportJob(
        jobId: id(200),
        sourceUserId: userA,
        manifestHash: 'a' * 64,
        resourceIds: [song, recording],
      );
      await a.saveSnapshotResume({
        'snapshot_id': id(300),
        'entity': 'SONG',
        'ordinal': 7,
      });
      await manager.logout();
      await expectLater(a.readLocalAudio(recording), throwsStateError);
      manager = makeManager();
      a = await manager.openAccount(userA);
      expect(await a.readLocalAudio(recording), audio);
      expect(await a.readJournal(recording), contains('preserved'));
      expect(await a.pendingImportJobs(), [id(200)]);
      expect(
        jsonDecode((await a.readSnapshotResume())!),
        containsPair('ordinal', 7),
      );
      expect(await a.readCursor(), isNull);
    },
  );

  test(
    'conflict baseline, cursor and import progress survive reopening',
    () async {
      var a = await manager.openAccount(userA);
      await a.createImportJob(
        jobId: id(200),
        sourceUserId: userA,
        manifestHash: 'a' * 64,
        resourceIds: [song, recording],
      );
      await manager.logout();
      var db = await raw(userA);
      await db.customStatement(
        'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,updated_at) VALUES(?,?,?,7,?,1)',
        [userA, 'SONG', song, '{"title":"server before"}'],
      );
      await db.close();
      a = await manager.openAccount(userA);
      await a.saveEdit(edit(100, base: 7, title: 'local draft'));
      await manager.logout();
      db = await raw(userA);
      await db.transaction(() async {
        await db.customStatement(
          'UPDATE metadata_copies SET server_revision=8,server_payload=?',
          ['{"title":"server after"}'],
        );
        await db.customStatement(
          "UPDATE local_mutations SET queue_state='CONFLICT',attempt_count=2,server_response=?",
          ['{"revision":8,"title":"server after"}'],
        );
        await db.customStatement(
          'UPDATE sync_cursors SET last_change_seq=42,baseline_complete=1',
        );
        await db.customStatement(
          "UPDATE import_items SET status='APPLIED',result_payload='{}' WHERE ordinal=1",
        );
        await db.customStatement(
          "UPDATE import_jobs SET status='PAUSED',completed_items=1",
        );
      });
      await db.close();
      manager = makeManager();
      a = await manager.openAccount(userA);
      final copy = (await a.readMetadata(LocalEntity.song, song))!;
      final mutation = (await a.pendingMutations()).single;
      expect(copy.revision, 8);
      expect(copy.serverJson, contains('server after'));
      expect(copy.localJson, contains('local draft'));
      expect(mutation.baseRevision, 7);
      expect(mutation.basePayload, contains('server before'));
      expect(mutation.serverResponse, contains('server after'));
      expect(mutation.state, 'CONFLICT');
      expect(mutation.attemptCount, 2);
      expect(await a.readCursor(), 42);
      expect(await a.pendingImportJobs(), [id(200)]);
      await manager.logout();
      db = await raw(userA);
      try {
        final job = await db
            .customSelect('SELECT * FROM import_jobs')
            .getSingle();
        expect(job.read<int>('completed_items'), 1);
        final item = await db
            .customSelect('SELECT * FROM import_items WHERE ordinal=1')
            .getSingle();
        expect(item.read<String>('status'), 'APPLIED');
      } finally {
        await db.close();
      }
    },
  );

  test(
    'completed files require final path, matching size and checksum',
    () async {
      final a = await manager.openAccount(userA);
      final location = await paths(userA);
      await (await location.checkedFile(location.audioPath(recording)))
          .writeAsBytes(audio);
      Future<void> register({bool pending = false, int? size, String? hash}) =>
          a.recordFileAndJournal(
            recordingId: recording,
            operationId: id(21),
            state: FilePresence.inputPending,
            phase: JournalPhase.verified,
            pending: pending,
            sizeBytes: size ?? audio.length,
            checksum: hash ?? digest,
            recovery: {},
          );
      await expectLater(register(pending: true), throwsArgumentError);
      await expectLater(register(size: audio.length + 1), throwsStateError);
      await expectLater(register(hash: 'a' * 64), throwsStateError);
      expect(await a.readJournal(recording), isNull);
      await register();
      expect(await a.readLocalAudio(recording), audio);
    },
  );

  test('dev and prod accounts never share the same local database', () async {
    final a = await manager.openAccount(userA);
    await a.saveEdit(edit(100));
    await manager.logout();
    final production = makeManager(environment: AppEnvironment.prod);
    try {
      final prod = await production.openAccount(userA);
      expect(await prod.pendingMutations(), isEmpty);
    } finally {
      await production.logout();
    }
    final reopened = await manager.openAccount(userA);
    expect(await reopened.pendingMutations(), hasLength(1));
  });

  test('copied foreign database refuses to open and is not reset', () async {
    final a = await manager.openAccount(userA);
    await a.saveEdit(edit(100));
    await manager.logout();
    final aFile = await (await paths(userA)).databaseFile();
    final bFile = await (await paths(userB)).databaseFile();
    await aFile.copy(bFile.path);
    await expectLater(
      manager.openAccount(userB),
      remoteFailure('Local database account/environment mismatch'),
    );
    final inspect = sqlite.sqlite3.open(bFile.path);
    try {
      expect(
        inspect.select('SELECT user_id FROM local_account').single['user_id'],
        userA,
      );
      expect(
        inspect.select('SELECT COUNT(*) AS n FROM local_mutations').single['n'],
        1,
      );
    } finally {
      inspect.close();
    }
  });

  test('future schema is rejected without destructive recovery', () async {
    final a = await manager.openAccount(userA);
    await a.saveEdit(edit(100));
    await manager.logout();
    final file = await (await paths(userA)).databaseFile();
    final future = sqlite.sqlite3.open(file.path);
    future.execute('PRAGMA user_version = 99');
    future.close();
    await expectLater(
      manager.openAccount(userA),
      remoteFailure('Unsupported local schema migration: 99 -> 5'),
    );
    final inspect = sqlite.sqlite3.open(file.path);
    try {
      expect(
        inspect.select('SELECT COUNT(*) AS n FROM local_mutations').single['n'],
        1,
      );
    } finally {
      inspect.close();
    }
  });

  test(
    'UUID scopes and typed relative paths reject traversal and object keys',
    () async {
      expect(() => manager.openAccount('../other'), throwsFormatException);
      await expectLater(
        manager.openAccount('00000000-0000-0000-0000-000000000000'),
        throwsArgumentError,
      );
      final location = await paths(userA);
      for (final malicious in [
        '../$userB/account.sqlite',
        'C:/recording.m4a',
        '/audio/x',
        'https://objects.example/a',
        's3/bucket/recording',
        'audio/../../other.m4a',
        'audio\\$recording.m4a',
      ]) {
        await expectLater(
          location.checkedFile(malicious),
          throwsArgumentError,
          reason: malicious,
        );
      }
    },
  );

  test('another account backup is not accepted as an import job', () async {
    final a = await manager.openAccount(userA);
    await expectLater(
      a.createImportJob(
        jobId: id(200),
        sourceUserId: userB,
        manifestHash: 'a' * 64,
        resourceIds: [song],
      ),
      throwsArgumentError,
    );
    expect(await a.pendingImportJobs(), isEmpty);
  });

  test('journal and file metadata are one transaction', () async {
    final a = await manager.openAccount(userA);
    await fileFixture(a);
    await expectLater(
      a.recordFileAndJournal(
        recordingId: id(22),
        operationId: id(21),
        state: FilePresence.interrupted,
        phase: JournalPhase.failed,
        pending: true,
        recovery: {'partial': true},
      ),
      remoteFailure(
        'UNIQUE constraint failed: recording_journals.operation_id',
      ),
    );
    expect(await a.readJournal(id(22)), isNull);
    await manager.logout();
    final db = await raw(userA);
    try {
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM local_recording_files')
                .getSingle())
            .read<int>('n'),
        1,
      );
    } finally {
      await db.close();
    }
  });

  test('journal cannot be claimed by a different operation', () async {
    final a = await manager.openAccount(userA);
    await fileFixture(a);
    await expectLater(
      a.recordFileAndJournal(
        recordingId: recording,
        operationId: id(99),
        state: FilePresence.saved,
        phase: JournalPhase.committed,
        pending: false,
        checksum: digest,
        sizeBytes: audio.length,
        recovery: {},
      ),
      throwsStateError,
    );
    expect(await a.readJournal(recording), contains('preserved'));
  });

  test(
    'registered file is rechecked at read and missing file stays recorded',
    () async {
      final a = await manager.openAccount(userA);
      await fileFixture(a);
      final location = await paths(userA);
      final file = await location.checkedFile(location.audioPath(recording));
      await file.writeAsBytes(List<int>.filled(audio.length, 0), flush: true);
      await expectLater(a.readLocalAudio(recording), throwsStateError);
      await file.delete(); // Only the synthetic test fixture.
      await expectLater(
        a.readLocalAudio(recording),
        throwsA(isA<FileSystemException>()),
      );
      expect(await a.readJournal(recording), contains('preserved'));
    },
  );

  test('symbolic-link file cannot expose another account recording', () async {
    final a = await manager.openAccount(userA);
    await fileFixture(a);
    final location = await paths(userA);
    final file = await location.checkedFile(location.audioPath(recording));
    final foreign = File(
      p.join((await paths(userB)).directory.path, 'private.txt'),
    );
    await foreign.writeAsBytes(audio);
    await file.delete();
    try {
      await Link(file.path).create(foreign.path);
    } on FileSystemException {
      if (Platform.isWindows) {
        markTestSkipped(
          'Windows symbolic-link privilege is unavailable; CI exercises this case.',
        );
        return;
      }
      rethrow;
    }
    await expectLater(a.readLocalAudio(recording), throwsStateError);
  });

  group('raw SQLite constraints', () {
    late AccountDatabase db;
    setUp(() async {
      db = AccountDatabase(
        NativeDatabase.memory(),
        userId: userA,
        environment: AppEnvironment.dev,
      );
      await db.verifyReady();
    });
    tearDown(() async {
      await db.close();
    });

    test('SQLite version and foreign keys are available', () async {
      expect(
        (await db.customSelect('SELECT sqlite_version() AS v').getSingle())
            .read<String>('v'),
        isNotEmpty,
      );
      expect(
        (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
          'foreign_keys',
        ),
        1,
      );
    });
    test('database owner cannot be changed or removed', () async {
      await expectLater(
        db.customStatement('UPDATE local_account SET user_id=?', [userB]),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        db.customStatement('DELETE FROM local_account'),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });
    test('foreign account metadata rejected', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO metadata_copies(user_id,entity_type,entity_id,updated_at) VALUES(?,?,?,1)',
          [userB, 'SONG', song],
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });
    test(
      'mutation identity and baseline stay immutable across retries',
      () async {
        await db.customStatement(
          'INSERT INTO metadata_copies(user_id,entity_type,entity_id,updated_at) VALUES(?,?,?,1)',
          [userA, 'SONG', song],
        );
        await db.customStatement(
          "INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at) VALUES(?,?,?,?,'CREATE',0,'{}',?,1,1)",
          [id(100), userA, 'SONG', song, 'a' * 64],
        );
        for (final assignment in [
          "op_id='${id(101)}'",
          "payload='{\"changed\":true}'",
          "base_revision=1,base_payload='{}'",
          "request_hash='${'b' * 64}'",
        ]) {
          await expectLater(
            db.customStatement('UPDATE local_mutations SET $assignment'),
            throwsA(isA<sqlite.SqliteException>()),
          );
        }
        await db.customStatement(
          "UPDATE local_mutations SET queue_state='RETRY',attempt_count=1",
        );
        await expectLater(
          db.customStatement('UPDATE local_mutations SET attempt_count=0'),
          throwsA(isA<sqlite.SqliteException>()),
        );
      },
    );
    test(
      'public chart and malformed JSON cannot enter personal copies',
      () async {
        await expectLater(
          db.customStatement(
            'INSERT INTO metadata_copies(user_id,entity_type,entity_id,updated_at) VALUES(?,?,?,1)',
            [userA, 'CHART_ITEM', song],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        await expectLater(
          db.customStatement(
            'INSERT INTO metadata_copies(user_id,entity_type,entity_id,local_payload,updated_at) VALUES(?,?,?,?,1)',
            [userA, 'SONG', song, '[]'],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
      },
    );
    test(
      'server object key is never accepted in local file path column',
      () async {
        await expectLater(
          db.customStatement(
            'INSERT INTO local_recording_files(recording_id,user_id,relative_path,local_state,updated_at) VALUES(?,?,?,?,1)',
            [recording, userA, 'recordings/server/object.m4a', 'CAPTURING'],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
      },
    );
    test('cursor cannot rewind or claim a baseline without a cursor', () async {
      await expectLater(
        db.customStatement('UPDATE sync_cursors SET baseline_complete=1'),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await db.customStatement(
        'UPDATE sync_cursors SET last_change_seq=9,baseline_complete=1',
      );
      await expectLater(
        db.customStatement('UPDATE sync_cursors SET last_change_seq=8'),
        throwsA(isA<sqlite.SqliteException>()),
      );
      await expectLater(
        db.customStatement('UPDATE sync_cursors SET last_change_seq=NULL'),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });
  });
}
