import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/trash_receipt.dart';

import 'change_payload_validation_test.dart' show songChange, recordingWire;

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late Map<String, dynamic> song, record;
  late DateTime deviceClock;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('song_record_offline_trash_');
    deviceClock = DateTime.utc(2026, 10, 11);
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
      clock: () => deviceClock,
    );
    await manager.openAccount(id(1));
    await manager.logout();
    final paths = await AccountPaths.create(root, id(1), AppEnvironment.dev);
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: id(1),
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    song = songChange(id(10), 1);
    record = recordingWire('RecordingEdited')
      ..['id'] = id(20)
      ..['song_id'] = id(10)
      ..['revision'] = 1
      ..['metadata_state'] = 'SAVED'
      ..['lifecycle_state'] = 'ACTIVE';
    for (final pair in [('SONG', song), ('RECORDING', record)]) {
      final value = canonicalJson(pair.$2);
      await db.customStatement(
        'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,local_payload,updated_at) VALUES(?,?,?,1,?,?,1)',
        [id(1), pair.$1, pair.$2['id'], value, value],
      );
    }
    await db.customStatement(
      'UPDATE sync_cursors SET baseline_complete=1,last_change_seq=1',
    );
    await db.close();
    await (await paths.checkedFile(paths.audioPath(id(20))))
        .writeAsBytes([1, 2, 3]);
    store = await manager.openAccount(id(1));
  });
  tearDown(() async {
    await manager.logout();
    expect(root.path, contains('song_record_offline_trash_'));
    await root.delete(recursive: true);
  });
  test('offline together hides immediately, survives restart and preserves original without a phone-clock expiry', () async {
    final save = LocalRepository(store, newId: () => id(100)).prepareTrash(
      entity: LocalEntity.song,
      expected: song,
      revision: 1,
      command: {'mode': 'SONG_AND_RECORDINGS', 'preview_version': 'a' * 64},
    );
    await save();
    deviceClock = deviceClock.add(const Duration(days: 40));
    expect(await store.readActiveSongs(), isEmpty);
    expect(await store.savedRecordings(), isEmpty);
    final before = await store.readMetadata(LocalEntity.song, id(10));
    expect(jsonDecode(before!.localJson!)['deleted_at'], isNull);
    expect(before.tombstone, isFalse);
    await manager.logout();
    store = await manager.openAccount(id(1));
    expect(await store.savedRecordings(), isEmpty);
    final paths = await AccountPaths.create(root, id(1), AppEnvironment.dev);
    expect(
      await (await paths.checkedFile(paths.audioPath(id(20)))).readAsBytes(),
      [1, 2, 3],
    );
    final request = await store.claimMutation();
    expect(request, isNotNull);
    expect(request!.path, '/v1/songs/${id(10)}/trash');
    final date = '2026-10-11T06:00:00Z';
    final receipt = {
      'batch_id': id(101),
      'mode': 'SONG_AND_RECORDINGS',
      'deleted_at': date,
      'purge_after': '2026-10-18T06:00:00Z',
      'song': {
        ...song,
        'revision': 2,
        'lifecycle_state': 'TRASHED',
        'deleted_at': date,
      },
      'recordings': [
        {
          ...record,
          'revision': 2,
          'song_id': null,
          'link_revision': (record['link_revision'] as int) + 1,
          'lifecycle_state': 'TRASHED',
          'deleted_at': date,
        },
      ],
    };
    expect(
      await store.acknowledgeTrash(
        request,
        MutationResponse(200, jsonEncode(receipt)),
      ),
      isTrue,
    );
    expect(await store.savedRecordings(), isEmpty);
    expect(
      jsonDecode(
        (await store.readMetadata(LocalEntity.song, id(10)))!.serverJson!,
      )['deleted_at'],
      date,
    );
    expect(
      await (await paths.checkedFile(paths.audioPath(id(20)))).exists(),
      isTrue,
    );
  });
  test('song-only offline projection keeps recording visible and unlinked without changing server baseline', () async {
    await LocalRepository(store, newId: () => id(102)).prepareTrash(
      entity: LocalEntity.song,
      expected: song,
      revision: 1,
      command: {'mode': 'SONG_ONLY', 'preview_version': 'b' * 64},
    )();
    expect(await store.readActiveSongs(), isEmpty);
    expect((await store.savedRecordings()).single['song_id'], isNull);
    final copy = await store.readMetadata(LocalEntity.recording, id(20));
    expect(jsonDecode(copy!.serverJson!)['song_id'], id(10));
    expect(copy.tombstone, isFalse);
  });
  test('old batch receipt cannot rewind a newer restored recording', () async {
    await LocalRepository(store, newId: () => id(120)).prepareTrash(
      entity: LocalEntity.song,
      expected: song,
      revision: 1,
      command: {'mode': 'SONG_AND_RECORDINGS', 'preview_version': 'c' * 64},
    )();
    final request = (await store.claimMutation())!;
    await manager.logout();
    final paths = await AccountPaths.create(root, id(1), AppEnvironment.dev);
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: id(1),
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    final newer = canonicalJson({
      ...record,
      'revision': 5,
      'song_id': null,
      'note': 'restored later',
    });
    await db.customStatement(
      "UPDATE metadata_copies SET server_revision=5,server_payload=?,local_payload=? WHERE entity_type='RECORDING' AND entity_id=?",
      [newer, newer, id(20)],
    );
    await db.close();
    store = await manager.openAccount(id(1));
    const date = '2026-10-11T06:00:00Z';
    final receipt = {
      'batch_id': id(121),
      'mode': 'SONG_AND_RECORDINGS',
      'deleted_at': date,
      'purge_after': '2026-10-18T06:00:00Z',
      'song': {
        ...song,
        'revision': 2,
        'lifecycle_state': 'TRASHED',
        'deleted_at': date,
      },
      'recordings': [
        {
          ...record,
          'revision': 2,
          'song_id': null,
          'lifecycle_state': 'TRASHED',
          'deleted_at': date,
        },
      ],
    };
    // Reopening retires the old SENDING attempt. Replay its immutable body in
    // the new attempt; the old callback itself must not acknowledge anything.
    expect(
      await store.acknowledgeTrash(
        request,
        MutationResponse(200, jsonEncode(receipt)),
      ),
      isFalse,
    );
    deviceClock = deviceClock.add(const Duration(hours: 1));
    final replay = (await store.claimMutation())!;
    expect(replay.body, request.body);
    expect(
      await store.acknowledgeTrash(
        replay,
        MutationResponse(200, jsonEncode(receipt)),
      ),
      isTrue,
    );
    expect(
      (await store.readMetadata(LocalEntity.recording, id(20)))!.revision,
      5,
    );
    expect((await store.savedRecordings()).single['note'], 'restored later');
  });
  test('individual queued trash and malformed lifetime do not erase original or acknowledge a failed receipt', () async {
    await LocalRepository(store, newId: () => id(103)).prepareTrash(
      entity: LocalEntity.recording,
      expected: record,
      revision: 1,
      command: {'base_revision': 1, 'pin_release_confirmed': true},
    )();
    expect(await store.savedRecordings(), isEmpty);
    final request = (await store.claimMutation())!;
    final result = {
      'batch_id': id(104),
      'deleted_at': '2026-10-11T00:00:00Z',
      'purge_after': '2026-10-19T00:00:00Z',
      'recording': {
        ...record,
        'revision': 2,
        'lifecycle_state': 'TRASHED',
        'deleted_at': '2026-10-11T00:00:00Z',
      },
    };
    expect(
      () => decodeTrashReceipt(
        request,
        MutationResponse(200, jsonEncode(result)),
      ),
      throwsFormatException,
    );
    expect(
      store.acknowledgeTrash(
        request,
        MutationResponse(200, jsonEncode(result)),
      ),
      throwsFormatException,
    );
    expect((await store.pendingMutations()).single.state, 'SENDING');
  });
}
