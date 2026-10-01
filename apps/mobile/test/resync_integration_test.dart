import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/change_feed_sync_backend.dart';
import 'package:song_record/features/sync/snapshot_sync_backend.dart';

import 'change_feed_receiver_test.dart' show FeedTransport;
import 'snapshot_receiver_test.dart' show FakeTransport;
import 'snapshot_sync_backend_test.dart' show Sender;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('expired delta receives and verifies a new 19-entity baseline before sending, preserving offline data', () async {
    const owner = '11111111-1111-4111-8111-111111111111',
        oldToken = '22222222-2222-4222-8222-222222222222',
        id = '33333333-3333-4333-8333-333333333333',
        newToken = '44444444-4444-4444-8444-444444444444',
        operation = '55555555-5555-4555-8555-555555555555';
    var now = DateTime.utc(2026, 9, 30);
    final directory = await Directory.systemTemp.createTemp(
      'sr-resync-integration-',
    );
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => directory,
      temporaryDirectory: () async => directory,
      clock: () => now,
    );
    try {
      final store = await manager.openAccount(owner);
      final text = File('../../fixtures/contracts/snapshot-wire.json')
          .readAsStringSync();
      final initial = jsonDecode(text) as Map;
      await store.beginSnapshotDownload(
        oldToken,
        jsonEncode(initial['manifest']),
      );
      for (final page in initial['pages'] as List) {
        await store.appendSnapshotPage(
          oldToken,
          page['entity'] as String,
          0,
          jsonEncode(page),
        );
      }
      await store.verifySnapshotDownload(oldToken);
      await store.applySnapshotDownload(oldToken);
      await store.saveEdit(
        LocalEdit(
          opId: operation,
          entity: LocalEntity.song,
          entityId: id,
          operation: LocalOperation.create,
          baseRevision: 0,
          draft: {'title': 'offline draft'},
          changes: {'title': 'offline draft'},
        ),
      );
      final paths = await AccountPaths.create(
        directory,
        owner,
        AppEnvironment.dev,
      );
      final audio = await paths.checkedFile(paths.audioPath(id));
      await audio.writeAsBytes([1, 2, 3, 4], flush: true);
      final before =
          (jsonDecode(await store.recoveryData()) as Map)['tables'] as Map;
      final fresh = jsonDecode(text.replaceAll(oldToken, newToken)) as Map;
      final snapshots = FakeTransport();
      snapshots.respond = (request) async {
        expect((await store.snapshotBaselinePage('SONG')).token, oldToken);
        if (request.method == 'POST') {
          expect(request.operationId, operation);
          return SnapshotHttpResponse(
            202,
            jsonEncode({
              'operation_id': operation,
              'snapshot_token': newToken,
              'status': 'BUILDING',
              'status_url': '/v1/sync/snapshots/$newToken',
            }),
          );
        }
        final entity = request.query['entity'];
        return SnapshotHttpResponse(
          200,
          jsonEncode(
            entity == null
                ? fresh['manifest']
                : (fresh['pages'] as List).singleWhere(
                    (page) => page['entity'] == entity,
                  ),
          ),
        );
      };
      final changes = FeedTransport();
      changes.respond = (request) async {
        expect(request.after, 7);
        if (changes.calls == 1) {
          return const ChangeFeedResponse(
            409,
            '{"error":{"code":"CURSOR_EXPIRED"}}',
          );
        }
        expect((await store.snapshotBaselinePage('SONG')).token, newToken);
        return const ChangeFeedResponse(
          200,
          '{"after_seq":7,"next_seq":7,"head_seq":7,"has_more":false,"changes":[]}',
        );
      };
      final auth = AuthSession(
        userId: owner,
        deviceId: owner,
        accessToken: 'synthetic',
        refreshToken: 'unused',
        accessExpiresAt: DateTime.utc(2030),
        refreshExpiresAt: DateTime.utc(2030),
      );
      final sender = Sender();
      final backend = SnapshotSyncBackend(
        receiver: SnapshotReceiver(
          store: store,
          transport: snapshots,
          newOperationId: () => operation,
          clock: () => now,
        ),
        session: () async => auth,
        now: () => now,
        outgoing: ChangeFeedSyncBackend(
          outgoing: sender,
          receiver: ChangeFeedReceiver(
            store: store,
            transport: changes,
            isSessionCurrent: (_) => true,
            newOperationId: () => operation,
          ),
          session: () async => auth,
          now: () => now,
          allowInitialRestart: true,
        ),
      );
      await backend.send();
      expect(sender.sends, 0);
      expect(await store.hasCompleteBaseline(), isFalse);
      for (var step = 0; step < 25 && sender.sends == 0; step++) {
        now = now.add(const Duration(seconds: 1));
        await backend.send();
      }
      expect(sender.sends, 1);
      expect(changes.calls, 2);
      expect(snapshots.requests, hasLength(21));
      expect((await store.snapshotBaselinePage('SONG')).token, newToken);
      expect(await store.readCursor(), 7);
      expect(await store.hasCompleteBaseline(), isTrue);
      expect(await store.readSnapshotResume(), isNull);
      final after =
          (jsonDecode(await store.recoveryData()) as Map)['tables'] as Map;
      for (final table in before.keys) {
        if (table != 'sync_cursors' &&
            !(table as String).startsWith('snapshot_')) {
          expect(after[table], before[table], reason: 'Preserve $table');
        }
      }
      expect(await audio.readAsBytes(), [1, 2, 3, 4]);
    } finally {
      await manager.logout();
      expect(
        directory.path.split(Platform.pathSeparator).last,
        startsWith('sr-resync-integration-'),
      );
      await directory.delete(recursive: true);
    }
  });
}
