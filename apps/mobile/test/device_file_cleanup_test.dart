import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/files/device_file_cleanup.dart';

import '../tool/local_preservation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  final owner = preservationId(1), id = preservationId(2);
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  final hash = sha256.convert(bytes).toString();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('device-cleanup-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(owner);
    await store.preserveDownloadedAudio(owner, id, hash, bytes.length, bytes);
    await store.saveEdit(
      LocalEdit(
        opId: preservationId(10),
        entity: LocalEntity.recording,
        entityId: id,
        operation: LocalOperation.create,
        baseRevision: 0,
        draft: {'title': 'synthetic metadata', 'lifecycle_state': 'ACTIVE'},
        changes: {'title': 'synthetic metadata'},
      ),
    );
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });
  test('no known server copy requires explicit loss ack; only device file disappears and metadata/mutations remain', () async {
    final flow = DeviceFileCleanup(store);
    final preview = await flow.preview(id);
    final metadata = await store.readMetadata(LocalEntity.recording, id);
    final tables =
        jsonDecode(await store.recoveryData())['tables']
            as Map<String, dynamic>;
    expect(preview.requiresLossAcknowledgement, isTrue);
    expect(preview.warning, contains('복구하지 못할 수'));
    await expectLater(
      flow.confirm(preview, confirmed: false, lossAcknowledged: true),
      throwsStateError,
    );
    await expectLater(
      flow.confirm(preview, confirmed: true, lossAcknowledged: false),
      throwsStateError,
    );
    expect(await store.readLocalAudio(id), bytes);
    await flow.confirm(preview, confirmed: true, lossAcknowledged: true);
    expect(await store.findPlayableLocalAudio(id), isNull);
    expect(
      (await store.readMetadata(LocalEntity.recording, id))!.localJson,
      metadata!.localJson,
    );
    final after =
        jsonDecode(await store.recoveryData())['tables']
            as Map<String, dynamic>;
    expect(after['local_mutations'], tables['local_mutations']);
    expect(
      (after['local_recording_files'] as List).single['local_state'],
      'MISSING',
    );
  });
  test(
    'pending durable fence prevents deletion across reopen; terminal releases',
    () async {
      var flow = DeviceFileCleanup(store);
      var preview = await flow.preview(id);
      final gen = preservationId(3), token = preservationId(4);
      await store.beginLocalCleanupFence(
        token: token,
        owner: owner,
        recording: id,
        generation: gen,
        checksum: hash,
        size: bytes.length,
        revision: 1,
        expires: DateTime.now().toUtc().add(const Duration(minutes: 14)),
      );
      await expectLater(
        flow.confirm(preview, confirmed: true, lossAcknowledged: true),
        throwsStateError,
      );
      expect(await store.readLocalAudio(id), bytes);
      await manager.logout();
      store = await manager.openAccount(owner);
      flow = DeviceFileCleanup(store);
      preview = await flow.preview(id);
      await expectLater(
        flow.confirm(preview, confirmed: true, lossAcknowledged: true),
        throwsStateError,
      );
      await store.finishLocalCleanupFence(token, gen, 'CANCELLED');
      await flow.confirm(preview, confirmed: true, lossAcknowledged: true);
      expect(await store.findPlayableLocalAudio(id), isNull);
    },
  );
  test(
    'changed bytes or account invalidates confirmation without deletion',
    () async {
      final flow = DeviceFileCleanup(store);
      final preview = await flow.preview(id);
      final source = await store.findPlayableLocalAudio(id);
      await File(source!.path).writeAsBytes([4, 3, 2, 1]);
      await expectLater(
        flow.confirm(preview, confirmed: true, lossAcknowledged: true),
        throwsStateError,
      );
      expect(await File(source.path).readAsBytes(), [4, 3, 2, 1]);
      await manager.openAccount(preservationId(99));
      await expectLater(
        flow.confirm(preview, confirmed: true, lossAcknowledged: true),
        throwsStateError,
      );
      expect(await File(source.path).exists(), isTrue);
    },
  );
  test('stored different bytes require loss ack and changed server evidence forces new preview', () async {
    Future<void> asset(String digest, int revision) async {
      await manager.logout();
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      final db = AccountDatabase(
        NativeDatabase(await paths.databaseFile()),
        userId: owner,
        environment: AppEnvironment.dev,
      );
      await db.verifyReady();
      final row = jsonEncode({
        'recording_id': id,
        'user_id': owner,
        'cloud_state': 'STORED',
        'generation': preservationId(3),
        'sha256': digest,
        'verified_size': bytes.length,
        'stored_at': '2026-10-09T00:00:00Z',
        'cloud_revision': revision,
      });
      await db.customStatement(
        'INSERT OR REPLACE INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,tombstone,updated_at) VALUES(?,?,?,?,?,0,1)',
        [owner, 'RECORDING_ASSET', id, revision, row],
      );
      await db.close();
      store = await manager.openAccount(owner);
    }

    await asset('f' * 64, 1);
    var flow = DeviceFileCleanup(store);
    var preview = await flow.preview(id);
    expect(preview.status.serverStored, isTrue);
    expect(preview.requiresLossAcknowledgement, isTrue);
    await expectLater(
      flow.confirm(preview, confirmed: true, lossAcknowledged: false),
      throwsStateError,
    );
    await asset(hash, 2);
    flow = DeviceFileCleanup(store);
    await expectLater(
      flow.confirm(preview, confirmed: true, lossAcknowledged: true),
      throwsStateError,
    );
    preview = await flow.preview(id);
    expect(preview.requiresLossAcknowledgement, isFalse);
    await flow.confirm(preview, confirmed: true, lossAcknowledged: false);
    expect(await store.findPlayableLocalAudio(id), isNull);
  });
}
