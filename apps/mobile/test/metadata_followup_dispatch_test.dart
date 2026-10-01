import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
const time = '2026-10-01T00:00:00Z';

Map<String, Object?> baseline(LocalEntity entity, String target) =>
    entity == LocalEntity.tag
    ? {
        'id': target,
        'name': 'before',
        'revision': 1,
        'archived_at': null,
        'updated_at': time,
      }
    : {
        'id': target,
        'title': 'before',
        'artist': 'artist',
        'revision': 1,
        'source_type': 'MANUAL',
        'tj_number': null,
        'version_code': 'NORMAL',
        'tier': null,
        'note': '',
        'lifecycle_state': 'ACTIVE',
        'updated_at': time,
        'representative_recording_id': null,
        'representative_key_mode': null,
        'representative_key_shift': null,
      };

class Transport implements MutationTransport {
  Transport(this.entity, {this.failParent = false, this.losePatch = false});
  final LocalEntity entity;
  final bool failParent, losePatch;
  final requests = <MutationRequest>[];
  int patchCalls = 0;
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    requests.add(request);
    final mutation = request.mutation;
    if (mutation.entityId == id(40)) {
      return MutationResponse(
        201,
        jsonEncode(baseline(LocalEntity.tag, id(40))),
      );
    }
    if (request.method == 'POST' && failParent) {
      return const MutationResponse(
        422,
        '{"error":{"code":"VALIDATION_FAILED"}}',
      );
    }
    final value = baseline(entity, mutation.entityId);
    if (request.method == 'PATCH') {
      final fields = Map<String, Object?>.from(jsonDecode(request.body) as Map)
        ..remove('base_revision');
      value.addAll(fields);
      value['revision'] = mutation.baseRevision + 1;
      if (losePatch && patchCalls++ == 0) {
        throw const MutationNetworkFailure(receivedStatus: 200);
      }
      return MutationResponse(200, jsonEncode(value));
    }
    return MutationResponse(
      201,
      jsonEncode(
        entity == LocalEntity.song
            ? {
                'created': true,
                'canonical_song_id': mutation.entityId,
                'song': value,
              }
            : value,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final entity in [LocalEntity.song, LocalEntity.tag]) {
    for (final scenario in ['success', 'lost response', 'parent failed']) {
      test('${entity.code} offline followup: $scenario preserves queue and file', () async {
        final root = await Directory.systemTemp.createTemp(
          'sr-metadata-followup-',
        );
        final manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => root,
          temporaryDirectory: () async => root,
        );
        final owner = id(1), target = id(10);
        Future<AuthSession> session() async => AuthSession(
          userId: owner,
          deviceId: id(2),
          accessToken: 'synthetic',
          refreshToken: 'unused',
          accessExpiresAt: DateTime.utc(2030),
          refreshExpiresAt: DateTime.utc(2030),
        );
        try {
          var store = await manager.openAccount(owner);
          var repository = LocalRepository(store);
          final field = entity == LocalEntity.tag ? 'name' : 'title';
          final create = repository.prepareCreate(
            entity: entity,
            entityId: target,
            draft: baseline(entity, target),
            changes: entity == LocalEntity.tag
                ? {'name': 'before'}
                : {
                    'source_type': 'MANUAL',
                    'title': 'before',
                    'artist': 'artist',
                    'manual_reason': 'TJ_NOT_FOUND',
                    'version_code': 'NORMAL',
                    'note': '',
                  },
          );
          await repository.save(create);
          final patch = repository.preparePatch(
            entity: entity,
            entityId: target,
            baseRevision: 0,
            draft: {...baseline(entity, target), field: 'after'},
            changes: {field: 'after'},
          );
          await repository.save(patch);
          // A later independent target must progress even if this parent fails.
          await repository.save(
            repository.prepareCreate(
              entity: LocalEntity.tag,
              entityId: id(40),
              draft: {'name': 'before'},
              changes: {'name': 'before'},
            ),
          );
          // P19's unimplemented wire adapter cannot consume or discard its queue.
          final playlist = repository.prepareCreate(
            entity: LocalEntity.playlist,
            entityId: id(50),
            draft: {'name': 'retained'},
            changes: {'name': 'retained'},
          );
          await repository.save(playlist);
          final originalPayload = (await repository.pending())
              .singleWhere((m) => m.opId == patch.opId)
              .payload;
          final paths = await AccountPaths.create(
            root,
            owner,
            AppEnvironment.dev,
          );
          final audio = await paths.checkedFile(paths.audioPath(id(70)));
          await audio.writeAsBytes([2, 4, 6, 8]);
          final transport = Transport(
            entity,
            failParent: scenario == 'parent failed',
            losePatch: scenario == 'lost response',
          );
          // End a bounded pass at CREATE, then reopen the database.
          expect(
            await repository.dispatch(
              transport: transport,
              session: session,
              limit: 1,
            ),
            scenario == 'parent failed' ? 0 : 1,
          );
          await manager.logout();
          store = await manager.openAccount(owner);
          repository = LocalRepository(store);
          expect(
            await repository.dispatch(transport: transport, session: session),
            scenario == 'success' ? 2 : 1,
          );
          if (scenario == 'lost response') {
            final lost = transport.requests.singleWhere(
              (r) => r.method == 'PATCH',
            );
            expect(
              await repository.retryMutation(
                lost.mutation.opId,
                expectedAttempt: 1,
              ),
              isTrue,
            );
            expect(
              await repository.dispatch(transport: transport, session: session),
              1,
            );
            final replay = transport.requests.last;
            expect(replay.mutation.opId, lost.mutation.opId);
            expect(replay.hash, lost.hash);
            expect(replay.body, lost.body);
          }
          final pending = await repository.pending();
          final original = pending.singleWhere((m) => m.opId == patch.opId);
          expect(original.payload, originalPayload);
          expect(original.attemptCount, 0);
          expect(original.baseRevision, 0);
          expect(original.state, 'PENDING');
          expect(
            (await repository.read(entity, target))!.localJson,
            contains('after'),
          );
          expect(
            (await repository.pendingWork()).map((m) => m.opId).toSet(),
            scenario == 'parent failed'
                ? {create.opId, patch.opId, playlist.opId}
                : {playlist.opId},
          );
          expect(
            transport.requests.where((r) => r.mutation.entityId == id(40)),
            hasLength(1),
          );
          expect(
            transport.requests.where(
              (r) => r.mutation.entity == LocalEntity.playlist,
            ),
            isEmpty,
          );
          expect(await repository.nextDispatchAt(), isNull);
          expect(await audio.readAsBytes(), [2, 4, 6, 8]);
          final exported = jsonDecode(await store.recoveryData()) as Map;
          expect(
            (exported['tables'] as Map)['recording_followups'],
            hasLength(scenario == 'parent failed' ? 0 : 1),
          );
        } finally {
          await manager.logout();
          await root.delete(recursive: true);
        }
      });
    }
  }
}
