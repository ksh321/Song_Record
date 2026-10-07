import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_response.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/change_feed_sync_backend.dart';
import 'package:song_record/features/sync/snapshot_sync_backend.dart';
import 'package:song_record/features/sync/sync_controller.dart';

import '../tool/sync_verification_fixture.dart';
import 'change_feed_receiver_test.dart' show FeedTransport;
import 'change_payload_validation_test.dart' show songChange;
import 'snapshot_receiver_test.dart' show FakeTransport;
import 'snapshot_sync_backend_test.dart' show Sender;
import 'support/business_snapshot_fixture.dart';

void main() {
  // VM tests: keep real loopback HTTP rather than the widget HTTP override.
  for (final scenario in ['ordinary', 'queued canonical', 'held pending']) {
    final canonical = scenario == 'queued canonical';
    final pending = scenario == 'held pending';
    test('HTTP resync resumes after expiry and truncation, then reviews $scenario edits', () async {
      final root = await Directory.systemTemp.createTemp('sr-resync-http-');
      final fixture = await SyncVerificationFixture.create(root, canonical: canonical,
        responseDelay: () async {});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var store = fixture.store;
      var repo = LocalRepository(store);
      var now = DateTime.now().toUtc();
      final owner = store.userId, target = fixtureId(canonical ? 21 : 10);
      final caughtUpCursor = pending ? 11 : 10;
      Map<String, List<Map<String, Object?>>> rows(int revision) => canonical
          ? {'SONG': [fixtureSong(target, revision, note: 'fresh server')]}
          : {'TAG': [fixtureTag(target, 'fresh server', revision)]};
      final auth = AuthSession(userId: owner, deviceId: fixtureId(2),
        accessToken: 'synthetic', refreshToken: 'unused',
        accessExpiresAt: DateTime.utc(2099), refreshExpiresAt: DateTime.utc(2099));
      var sequence = 300, creates = 0, pageCount = 0, patches = 0;
      var interrupted = false, reopened = false;
      Map<String, dynamic>? download;
      final operations = <String>[];
      final paths = await AccountPaths.create(
        (await root.list().where((e) => e is Directory).first) as Directory,
        owner, AppEnvironment.dev);
      final recording = fixtureId(50);
      final audio = await paths.checkedFile(paths.audioPath(recording));
      final bytes = List<int>.generate(32, (i) => i);
      try {
        await installVerificationSnapshot(store, verificationSnapshot(owner: owner,
          token: fixtureId(200), cursor: 7, now: now, rows: rows(canonical ? 2 : 1)));
        if (canonical) {
          await repo.resolveCanonical((await repo.canonicalCandidates()).single, ConflictChoice.local);
        }
        if (pending) {
          final conflict = (await repo.pendingWork()).single;
          await repo.save(repo.preparePatch(entity: LocalEntity.tag,
            entityId: target, baseRevision: 1,
            draft: fixtureTag(target, 'later local edit', 1),
            changes: {'name': 'later local edit'}));
          await repo.resolve(await repo.review(conflict.opId),
            {'name': ConflictChoice.server});
          final held = (await repo.pendingWork()).single;
          expect(held.state, 'PENDING');
          expect(held.serverResponse, isNull);
          expect(await store.claimMutation(), isNull);
        }
        await audio.writeAsBytes(bytes, flush: true);
        await store.recordFileAndJournal(recordingId: recording, operationId: fixtureId(51),
          state: FilePresence.inputPending, phase: JournalPhase.committed, pending: false,
          checksum: sha256.convert(bytes).toString(), sizeBytes: bytes.length,
          recovery: {'synthetic': true});
        Future<Map<String, dynamic>> tables() async =>
          (jsonDecode(await store.recoveryData()) as Map<String, dynamic>)['tables'] as Map<String, dynamic>;
        final before = await tables();
        final original = (await repo.pendingWork()).single;
        server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          Object value;
          if (request.uri.path == '/v1/sync/changes') {
            final after = int.parse(request.uri.queryParameters['after_seq']!);
            if (after == 7) {
              request.response.statusCode = 409;
              value = {'error': {'code': 'CURSOR_EXPIRED'}};
            } else if (pending && after == 10) {
              value = {'after_seq': 10, 'next_seq': 11, 'head_seq': 11,
                'has_more': false, 'changes': [
                  {'change_seq': 11, 'entity_type': 'TAG', 'entity_id': target,
                    'revision': 4, 'operation': 'UPSERT',
                    'payload': fixtureTag(target, 'latest delta name', 4)},
                ]};
            } else {
              value = {'after_seq': after, 'next_seq': after, 'head_seq': after,
                'has_more': false, 'changes': <Object?>[]};
            }
          } else if (request.method == 'POST') {
            await request.drain<void>();
            operations.add(request.headers.value('Idempotency-Key')!);
            final token = fixtureId(210 + creates++);
            download = verificationSnapshot(owner: owner, token: token, cursor: 10,
              now: now, rows: rows(3));
            request.response.statusCode = 202;
            value = {'operation_id': operations.last, 'snapshot_token': token,
              'status': 'BUILDING', 'status_url': '/v1/sync/snapshots/$token'};
          } else if (request.method == 'PATCH') {
            expect(await store.hasCompleteBaseline(), isTrue);
            expect(await store.readCursor(), caughtUpCursor);
            final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            patches++;
            if (canonical && patches == 1) {
              request.response.statusCode = 409;
              value = {'error': {'code': 'REVISION_CONFLICT',
                'details': {'current_revision': 4,
                  'current': fixtureSong(target, 4, note: 'newer server')}}};
            } else {
              value = canonical
                ? {...fixtureSong(target, (body['base_revision'] as int) + 1),
                    ...Map<String, dynamic>.from(body)..remove('base_revision'),
                    'revision': (body['base_revision'] as int) + 1}
                : fixtureTag(target, body['name'] as String, (body['base_revision'] as int) + 1);
            }
          } else {
            final entity = request.uri.queryParameters['entity'];
            if (entity == null) {
              value = download!['manifest'] as Map<String, dynamic>;
            } else if (creates == 1 && pageCount++ == 3) {
              request.response.statusCode = 410;
              value = {'error': {'code': 'SNAPSHOT_EXPIRED'}};
            } else {
              value = (download!['pages'] as List<dynamic>)
                .singleWhere((dynamic p) => p['entity'] == entity) as Map<String, dynamic>;
              if (creates == 2 && !interrupted) {
                interrupted = true;
                final data = utf8.encode(jsonEncode(value));
                request.response.contentLength = data.length;
                final socket = await request.response.detachSocket();
                socket.add(data.take(data.length ~/ 2).toList());
                await socket.flush(); socket.destroy();
                return;
              }
            }
          }
          request.response.write(jsonEncode(value));
          await request.response.close();
        });
        final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
        SnapshotSyncBackend backend() => SnapshotSyncBackend(
          receiver: SnapshotReceiver(store: store,
            transport: HttpSnapshotTransport(endpoint, allowLocalHttp: true),
            newOperationId: () => fixtureId(sequence++), clock: () => now),
          session: () async => auth, now: () => now,
          outgoing: ChangeFeedSyncBackend(
            receiver: ChangeFeedReceiver(store: store,
              transport: HttpChangeFeedTransport(endpoint, allowLocalHttp: true),
              isSessionCurrent: (_) => true, newOperationId: () => fixtureId(sequence++)),
            outgoing: RepositorySyncBackend(repo,
              HttpMutationTransport(endpoint, allowLocalHttp: true), () async => auth),
            session: () async => auth, now: () => now, allowInitialRestart: true));
        var receiving = backend();
        for (var step = 0; step < 65; step++) {
          try { await receiving.send(); } on AuthFailure {
            expect(interrupted, isTrue);
            expect(reopened, isFalse);
            final retained = await tables();
            for (final name in before.keys.where((n) => !n.startsWith('snapshot_') && n != 'sync_cursors')) {
              expect(retained[name], before[name], reason: name);
            }
            await fixture.manager.logout();
            store = await fixture.manager.openAccount(owner); repo = LocalRepository(store);
            expect(await tables(), retained);
            receiving = backend(); reopened = true;
          }
          now = now.add(const Duration(seconds: 6));
          if (await store.readCursor() == caughtUpCursor && await store.hasCompleteBaseline()) break;
        }
        expect(reopened, isTrue);
        expect(creates, 2); expect(operations.toSet(), hasLength(2));
        expect(await store.readCursor(), caughtUpCursor);
        if (pending) {
          final beforeReopen = await tables();
          await fixture.manager.logout();
          store = await fixture.manager.openAccount(owner);
          repo = LocalRepository(store);
          receiving = backend();
          expect(await tables(), beforeReopen);
          final held = (await repo.pendingWork()).single;
          expect(held.opId, original.opId);
          expect(held.state, 'PENDING');
          expect(held.serverResponse, isNull);
          expect(patches, 0);
          expect(await store.claimMutation(), isNull);
          final received = await tables();
          for (final name in ['local_mutations', 'mutation_wire_requests',
              'mutation_retry_controls', 'mutation_conflict_resolutions', 'pending_edit_resolutions']) {
            expect(before.containsKey(name), isTrue, reason: name);
            expect(received[name], before[name], reason: name);
          }
        }
        final review = await repo.review(original.opId);
        expect(review.server['revision'], canonical || pending ? 4 : 3);
        if (pending) expect(review.server['name'], 'latest delta name');
        expect(review.mutation.payload, original.payload);
        await repo.resolve(review, {canonical ? 'note' : 'name': ConflictChoice.local});
        await receiving.send();
        expect(patches, canonical ? 2 : 1);
        expect(await repo.pendingWork(), isEmpty);
        if (canonical) expect(await repo.canonicalCandidates(), isEmpty);
        final after = await tables();
        if (pending) {
          final originals = before['local_mutations'] as List<dynamic>;
          final mutations = after['local_mutations'] as List<dynamic>;
          for (final row in originals.cast<Map<String, dynamic>>()) {
            expect(mutations.singleWhere((dynamic m) => m['op_id'] == row['op_id']), row);
          }
          for (final name in ['mutation_wire_requests', 'mutation_retry_controls']) {
            for (final row in (before[name] as List<dynamic>).cast<Map<String, dynamic>>()) {
              expect((after[name] as List<dynamic>).singleWhere(
                (dynamic m) => m['op_id'] == row['op_id']), row);
            }
          }
          expect(after['mutation_conflict_resolutions'], before['mutation_conflict_resolutions']);
          expect(after['pending_edit_resolutions'], hasLength(1));
          final resolution = (after['pending_edit_resolutions'] as List<dynamic>).single as Map;
          expect(resolution['original_op_id'], original.opId);
          expect(resolution['logical_order'], original.localOrder);
          expect(jsonDecode(resolution['original_evidence'] as String),
            originals.singleWhere((dynamic m) => m['op_id'] == original.opId));
          expect(mutations.singleWhere((dynamic m) =>
            m['op_id'] == resolution['replacement_op_id']),
            containsPair('queue_state', 'ACKED'));
        }
        expect(after['local_recording_files'], before['local_recording_files']);
        expect(after['recording_journals'], before['recording_journals']);
        expect(await audio.readAsBytes(), bytes);
        expect(sha256.convert(await audio.readAsBytes()).toString(), sha256.convert(bytes).toString());
        await fixture.manager.logout();
        store = await fixture.manager.openAccount(owner);
        expect(await store.pendingWorkMutations(), isEmpty);
        if (pending) expect(await tables(), after);
        final old = store;
        store = await fixture.manager.openAccount(fixtureId(999));
        expect(await store.readMetadata(canonical ? LocalEntity.song : LocalEntity.tag, target), isNull);
        await expectLater(old.readCursor(), throwsStateError);
      } finally {
        await server.close(force: true); await fixture.close();
        expect(root.path.split(Platform.pathSeparator).last, startsWith('sr-resync-http-'));
        await root.delete(recursive: true);
      }
    });
  }
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
          final baseline =
          (await store.readMetadata(LocalEntity.song, id))!;
          final draft = Map<String, dynamic>.from(
            jsonDecode(baseline.serverJson!) as Map,
          )..['note'] = 'offline draft';

          await store.saveEdit(
            LocalEdit(
              opId: operation,
              entity: LocalEntity.song,
              entityId: id,
              operation: LocalOperation.patch,
              baseRevision: baseline.revision,
              draft: draft,
              changes: {
                'base_revision': baseline.revision,
                'note': 'offline draft',
              },
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
          expect(jsonDecode(copy.localJson!)['note'], 'offline draft');
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
            expect(jsonDecode(preserved.localJson!)['note'], 'offline draft');
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
