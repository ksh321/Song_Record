import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_response.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'change_payload_validation_test.dart' show songChange;
import 'metadata_dispatcher_test.dart' show FakeTransport;
import 'support/business_snapshot_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('received newer revision reaches actual conflict receipt without rewriting offline edit', () async {
    const owner = '11111111-1111-4111-8111-111111111111';
    const target = '33333333-3333-4333-8333-333333333333';
    final root = await Directory.systemTemp.createTemp('sr-received-conflict-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
      clock: () => DateTime.utc(2026, 9, 30),
    );
    try {
      var store = await manager.openAccount(owner);
      final fixture = businessSnapshotFixture();
      final token = fixture['manifest']['snapshot_token'] as String;
      await store.beginSnapshotDownload(token, jsonEncode(fixture['manifest']));
      for (final page in fixture['pages'] as List) {
        await store.appendSnapshotPage(
          token,
          page['entity'] as String,
          0,
          jsonEncode(page),
        );
      }
      await store.verifySnapshotDownload(token);
      await store.applySnapshotDownload(token);
      ChangeFeedPage page(List<Map<String, Object?>> changes, int next) =>
          ChangeFeedPage.decode(
            jsonEncode({
              'after_seq': 7,
              'next_seq': next,
              'head_seq': next,
              'has_more': false,
              'changes': changes,
            }),
            owner: owner,
            expectedAfter: 7,
          );
      await store.applyChangeFeed(page([], 7), snapshotToken: token);
      var repository = LocalRepository(store);
      final beforeCopy = (await store.readMetadata(LocalEntity.song, target))!;
      await repository.save(
        repository.preparePatch(
          entity: LocalEntity.song,
          entityId: target,
          baseRevision: 1,
          draft: {
            ...jsonDecode(beforeCopy.serverJson!) as Map<String, dynamic>,
            'note': 'my offline note',
          },
          changes: {'note': 'my offline note'},
        ),
      );
      final original = (await store.pendingMutations()).single;
      final remote = {...songChange(target, 2), 'note': 'other device note'};
      await store.applyChangeFeed(
        page([
          {
            'change_seq': 8,
            'entity_type': 'SONG',
            'entity_id': target,
            'revision': 2,
            'operation': 'UPSERT',
            'payload': remote,
          },
        ], 8),
        snapshotToken: token,
      );
      await manager.logout();
      store = await manager.openAccount(owner);
      repository = LocalRepository(store);
      final auth = AuthSession(
        userId: owner,
        deviceId: owner,
        accessToken: 'synthetic',
        refreshToken: 'unused',
        accessExpiresAt: DateTime.utc(2030),
        refreshExpiresAt: DateTime.utc(2030),
      );
      final transport = FakeTransport((request) async {
        expect(request.body, original.payload);
        expect(request.mutation.opId, original.opId);
        return MutationResponse(
          409,
          jsonEncode({
            'error': {
              'code': 'REVISION_CONFLICT',
              'details': {'current_revision': 2, 'current': remote},
            },
          }),
        );
      });
      await repository.dispatch(
        transport: transport,
        session: () async => auth,
      );
      expect(transport.calls, 1);
      final conflict = (await store.pendingMutations()).single;
      expect(conflict.state, 'CONFLICT');
      expect(conflict.payload, original.payload);
      expect(conflict.basePayload, original.basePayload);
      expect(conflict.baseRevision, 1);
      final review = await repository.review(original.opId);
      expect(review.comparison.requiresChoice, isTrue);
      expect(review.local['note'], 'my offline note');
      expect(review.server['note'], 'other device note');
      final newest = {...remote, 'revision': 3, 'note': 'newest server note'};
      await store.applyChangeFeed(ChangeFeedPage.decode(jsonEncode({
        'after_seq': 8, 'next_seq': 9, 'head_seq': 9, 'has_more': false,
        'changes': [{'change_seq': 9, 'entity_type': 'SONG', 'entity_id': target,
          'revision': 3, 'operation': 'UPSERT', 'payload': newest}],
      }), owner: owner, expectedAfter: 8), snapshotToken: token);
      await expectLater(repository.resolve(review, {'note': ConflictChoice.local}), throwsStateError);
      final refreshed = await repository.review(original.opId);
      expect(refreshed.server['revision'], 3);
      expect(refreshed.mutation.serverResponse, conflict.serverResponse);
      await repository.resolve(refreshed, {'note': ConflictChoice.local});
      final replacement = (await store.pendingWorkMutations()).single;
      expect(replacement.opId, isNot(original.opId));
      expect(replacement.baseRevision, 3);
      final ack = FakeTransport((request) async {
        expect(request.mutation.opId, replacement.opId);
        return MutationResponse(
          200,
          jsonEncode({...newest, 'revision': 4, 'note': 'my offline note'}),
        );
      });
      expect(
        await repository.dispatch(transport: ack, session: () async => auth),
        1,
      );
      expect(await store.pendingWorkMutations(), isEmpty);
      expect(
        jsonDecode(
          (await store.readMetadata(LocalEntity.song, target))!.serverJson!,
        )['note'],
        'my offline note',
      );
    } finally {
      await manager.logout();
      expect(
        root.path.split(Platform.pathSeparator).last,
        startsWith('sr-received-conflict-'),
      );
      await root.delete(recursive: true);
    }
  });
}
