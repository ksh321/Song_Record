import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_response.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/change_feed_sync_backend.dart';
import 'package:song_record/features/sync/snapshot_sync_backend.dart';

import 'change_feed_receiver_test.dart' show FeedTransport;
import 'change_payload_validation_test.dart' show songChange;
import 'snapshot_receiver_test.dart' show FakeTransport;
import 'snapshot_sync_backend_test.dart' show Sender;
import 'support/business_snapshot_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final permanentlyDeleted in [false, true]) {
    test(
      '${permanentlyDeleted ? "deleted target: " : ""}expired delta receives and verifies a new 19-entity baseline before sending, preserving offline data',
      () async {
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
          final text = jsonEncode(businessSnapshotFixture());
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
          final fresh = jsonDecode(
            text.replaceAll(oldToken, newToken),
          ) as Map<String, dynamic>;
          if (permanentlyDeleted) {
            final pages = fresh['pages'] as List;
            (pages.singleWhere((p) => p['entity'] == 'SONG')
                    as Map)['entries'] =
                <Object?>[];
            const ledgerId = '66666666-6666-4666-8666-666666666666';
            final deletion = <String, Object?>{
              'id': ledgerId,
              'user_id': owner,
              'entity_type': 'SONG',
              'entity_id': id,
              'revision': 5,
              'object_generation': null,
              'purged_at': '2026-09-30T00:00:00Z',
            };
            (pages.singleWhere((p) => p['entity'] == 'DELETION_LEDGER')
                as Map)['entries'] = [
              {
                'ordinal': 1,
                'resource_id': ledgerId,
                'payload': deletion,
                'canonical_payload': canonicalJson(deletion),
              },
            ];
            final counts = fresh['manifest']['entity_counts'] as Map;
            counts['SONG'] = 0;
            counts['DELETION_LEDGER'] = 1;
            refreshSnapshotHash(fresh);
          }
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
                table != 'metadata_copies' &&
                !(table as String).startsWith('snapshot_')) {
              expect(after[table], before[table], reason: 'Preserve $table');
            }
          }
          final copy = (await store.readMetadata(LocalEntity.song, id))!;
          final oldCopies = before['metadata_copies'] as List;
          final newCopies = after['metadata_copies'] as List;
          expect(newCopies.length, oldCopies.length);
          for (var index = 0; index < oldCopies.length; index++) {
            final oldCopy = oldCopies[index] as Map;
            final newCopy = newCopies[index] as Map;
            for (final key in oldCopy.keys) {
              if (!{
                'server_revision',
                'server_payload',
                'updated_at',
                if (permanentlyDeleted) 'tombstone',
              }.contains(key)) {
                expect(
                  newCopy[key],
                  oldCopy[key],
                  reason: 'Preserve metadata $key',
                );
              }
            }
          }
          expect(copy.revision, permanentlyDeleted ? 5 : 1);
          expect(copy.tombstone, permanentlyDeleted);
          expect(jsonDecode(copy.localJson!)['title'], 'offline draft');
          if (permanentlyDeleted) {
            expect(jsonDecode(copy.serverJson!), {
              'id': id,
              'entity_type': 'SONG',
              'revision': 5,
              'status': 'DELETED',
              'deleted_at': '2026-09-30T00:00:00Z',
            });
          } else {
            expect(jsonDecode(copy.serverJson!)['note'], '한글 🎵');
          }
          expect(await audio.readAsBytes(), [1, 2, 3, 4]);
          if (permanentlyDeleted) {
            await manager.logout();
            final reopened = await manager.openAccount(owner);
            final beforeRejected = jsonDecode(
              await reopened.recoveryData(),
            )['tables'];
            final resurrection = ChangeFeedPage.decode(
              jsonEncode({
                'after_seq': 7,
                'next_seq': 8,
                'head_seq': 8,
                'has_more': false,
                'changes': [
                  {
                    'change_seq': 8,
                    'entity_type': 'SONG',
                    'entity_id': id,
                    'revision': 6,
                    'operation': 'UPSERT',
                    'payload': songChange(id, 6),
                  },
                ],
              }),
              owner: owner,
              expectedAfter: 7,
            );
            await expectLater(
              reopened.applyChangeFeed(resurrection, snapshotToken: newToken),
              throwsStateError,
            );
            expect(
              jsonDecode(await reopened.recoveryData())['tables'],
              beforeRejected,
            );
            expect(await reopened.readCursor(), 7);
            final preserved = (await reopened.readMetadata(
              LocalEntity.song,
              id,
            ))!;
            expect(preserved.tombstone, isTrue);
            expect(jsonDecode(preserved.localJson!)['title'], 'offline draft');
            expect(await audio.readAsBytes(), [1, 2, 3, 4]);
          }
        } finally {
          await manager.logout();
          expect(
            directory.path.split(Platform.pathSeparator).last,
            startsWith('sr-resync-integration-'),
          );
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
