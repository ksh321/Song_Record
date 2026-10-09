import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/files/cleanup_confirmation.dart';
import 'package:song_record/core/files/local_preservation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../tool/local_preservation_fixture.dart';

final class LostConfirmation implements CleanupTransport {
  LostConfirmation(this.store);
  final AccountStore store;
  @override
  Future<void> confirmLocal(
    CleanupToken token,
    String operation,
    Future<void> Function() guard,
  ) async {
    await guard();
    expect((await store.pendingLocalCleanup()).single['token'], token.token);
    throw const CleanupNetworkFailure();
  }
}

final class CleanupResult implements CleanupStatusTransport {
  CleanupResult(this.state);
  final String? state;
  @override
  Future<String?> terminal(
    CleanupToken token,
    Future<void> Function() guard,
  ) async {
    await guard();
    return state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('response loss, reopen and expiry keep the actual file fenced until a matching terminal result', () async {
    final root = await Directory.systemTemp.createTemp('cleanup-fence-');
    var now = DateTime.now().toUtc();
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
      clock: () => now,
    );
    final bytes = Uint8List.fromList(
      utf8.encode('synthetic persistent cleanup copy'),
    );
    final owner = preservationId(1),
        id = preservationId(2),
        gen = preservationId(3),
        tokenId = preservationId(4);
    final object = PreservationObject(
      owner: owner,
      recording: id,
      generation: gen,
      checksum: sha256.convert(bytes).toString(),
      size: bytes.length,
      revision: 3,
    );
    final token = CleanupToken(
      tokenId,
      object,
      now.add(const Duration(minutes: 15)),
    );
    try {
      var store = await manager.openAccount(owner);
      final flow = LocalCleanupCoordinator(
        store,
        LocalPreservation(store, SyntheticPreservationDownload(bytes)),
        LostConfirmation(store),
      );
      await expectLater(
        flow.confirm(token, operation: preservationId(5)),
        throwsA(isA<CleanupNetworkFailure>()),
      );
      expect((await store.pendingLocalCleanup()).single['state'], 'PREPARING');
      await manager.logout();
      store = await manager.openAccount(owner);
      expect((await store.pendingLocalCleanup()).single['token'], tokenId);
      now = now.add(const Duration(minutes: 16));
      await expectLater(
        store.beginLocalCleanupFence(
          token: preservationId(6),
          owner: owner,
          recording: id,
          generation: gen,
          checksum: object.checksum,
          size: bytes.length,
          revision: 3,
          expires: token.expires,
        ),
        throwsStateError,
      );
      expect((await store.pendingLocalCleanup()).single['state'], 'PREPARING');
      await expectLater(
        store.preserveDownloadedAudio(
          owner,
          id,
          object.checksum,
          bytes.length,
          bytes,
        ),
        throwsStateError,
      );
      await expectLater(
        store.finishLocalCleanupFence(tokenId, preservationId(7), 'SUCCEEDED'),
        throwsStateError,
      );
      await expectLater(
        store.finishLocalCleanupFence(tokenId, gen, 'DELETING'),
        throwsStateError,
      );
      final resumed = LocalCleanupCoordinator(
        store,
        LocalPreservation(store, SyntheticPreservationDownload(bytes)),
        LostConfirmation(store),
      );
      await resumed.resume(CleanupResult(null));
      expect((await store.pendingLocalCleanup()).single['state'], 'PREPARING');
      await resumed.resume(CleanupResult('EXPIRED'));
      await resumed.resume(CleanupResult('EXPIRED'));
      expect(await store.pendingLocalCleanup(), isEmpty);
      expect(await store.readLocalAudio(id), bytes);
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
  test(
    'v10 migration preserves offline metadata, original bytes and file records',
    () async {
      final root = await Directory.systemTemp.createTemp('cleanup-migration-');
      final owner = preservationId(10), id = preservationId(11);
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final digest = sha256.convert(data).toString();
      await (await paths.checkedFile(paths.audioPath(id)))
          .writeAsBytes(data, flush: true);
      final old = sqlite.sqlite3.open((await paths.databaseFile()).path);
      old.execute(
        await File('test/fixtures/local_schema_v10.sql').readAsString(),
      );
      old.execute(
        "INSERT INTO local_account(singleton,user_id,environment,created_at) VALUES(1,?,'dev',0)",
        [owner],
      );
      old.execute(
        'INSERT INTO sync_cursors(singleton,user_id,updated_at) VALUES(1,?,0)',
        [owner],
      );
      old.execute(
        "INSERT INTO local_recording_files(recording_id,user_id,relative_path,sha256,size_bytes,local_state,verified_at,updated_at) VALUES(?,?,?,?,4,'SAVED',0,0)",
        [id, owner, paths.audioPath(id), digest],
      );
      old.execute(
        "INSERT INTO metadata_copies(user_id,entity_type,entity_id,local_payload,updated_at) VALUES(?,'SONG',?, ?,0)",
        [owner, preservationId(12), '{"title":"offline"}'],
      );
      old.execute('UPDATE local_recording_files SET cleanup_fence=2');
      old.execute('PRAGMA user_version=10');
      old.close();
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => root,
        temporaryDirectory: () async => root,
      );
      try {
        final store = await manager.openAccount(owner);
        expect(await store.readLocalAudio(id), data);
        final exported = jsonDecode(await store.recoveryData()) as Map;
        expect(exported['schema_version'], 11);
        final tables = exported['tables'] as Map;
        expect(
          (tables['metadata_copies'] as List).single['local_payload'],
          '{"title":"offline"}',
        );
        expect(tables['local_cleanup_confirmations'], isEmpty);
        expect(
          (tables['local_recording_files'] as List).single['cleanup_fence'],
          2,
        );
      } finally {
        await manager.logout();
        await root.delete(recursive: true);
      }
    },
  );
}
