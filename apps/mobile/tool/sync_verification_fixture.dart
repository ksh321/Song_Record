import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/canonical_conflict_plan.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/conflict_review.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/sync_controller.dart';

String fixtureId(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
Map<String, Object?> fixtureTag(String id, String name, int revision) => {
  'id': id,
  'name': name,
  'revision': revision,
  'archived_at': null,
  'updated_at': '2026-10-01T00:00:00Z',
};

Map<String, Object?> fixtureSong(String id, int revision, {String note = '서버 메모'}) => {
  'id': id, 'revision': revision, 'updated_at': '2026-10-01T00:00:00Z',
  'source_type': 'TJ', 'tj_number': '12345', 'title': '합성 곡',
  'artist': '합성 가수', 'version_code': 'NORMAL', 'tier': null, 'note': note,
  'lifecycle_state': 'ACTIVE', 'representative_key_mode': null,
  'representative_key_shift': null, 'representative_recording_id': null,
};

/// No HTTP implementation or credentials: responses are synthetic and local.
final class VerificationTransport implements MutationTransport {
  VerificationTransport(this.status, this.responseDelay);
  final int? status;
  final Future<void> Function() responseDelay;
  int calls = 0;
  final started = Completer<void>();
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() current,
  ) async {
    current();
    calls++;
    if (!started.isCompleted) started.complete();
    if (status != null) {
      await responseDelay();
      current();
      return MutationResponse(status!, '{"error":{"code":"UNAUTHENTICATED"}}');
    }
    final body = jsonDecode(request.body) as Map;
    if (request.mutation.entity == LocalEntity.song) {
      await responseDelay();
      current();
      return MutationResponse(200, jsonEncode({
        ...fixtureSong(request.mutation.entityId, request.mutation.baseRevision + 1),
        ...Map<String, dynamic>.from(body)..remove('base_revision'),
        'revision': request.mutation.baseRevision + 1,
      }));
    }
    return MutationResponse(
      200,
      jsonEncode(
        fixtureTag(request.mutation.entityId, body['name'] as String, 3),
      ),
    );
  }
}

final class SyncVerificationFixture {
  SyncVerificationFixture._(
    this.manager,
    this.store,
    this.controller,
    this.transport,
  );
  final AccountStoreManager manager;
  final AccountStore store;
  final SyncController controller;
  final VerificationTransport transport;

  /// Each run gets a fresh child directory. Existing runs are never cleared.
  static Future<SyncVerificationFixture> create(
    Directory root, {
    int? authenticationStatus,
    Future<void> Function()? responseDelay,
    bool canonical = false,
    bool changeOnReview = false,
  }) async {
    if (authenticationStatus != null &&
        authenticationStatus != 401 &&
        authenticationStatus != 403) {
      throw ArgumentError('Only 401/403 verification scenarios are supported');
    }
    await root.create(recursive: true);
    final run = await root.createTemp('sync-verification-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => run,
      temporaryDirectory: () async => run,
    );
    try {
      final store = await manager.openAccount(fixtureId(1));
      final repository = LocalRepository(store);
      final transport = VerificationTransport(
        authenticationStatus,
        responseDelay ?? () => Future<void>.delayed(const Duration(seconds: 8)),
      );
      if (canonical) {
        await repository.save(repository.prepareCreate(
          entity: LocalEntity.song, entityId: fixtureId(20),
          draft: fixtureSong(fixtureId(20), 0, note: '이 기기 개인 메모'),
          changes: {'id': fixtureId(20), 'source_type': 'TJ',
            'source_token': 'synthetic-proof', 'note': '이 기기 개인 메모'},
        ));
        final request = (await store.claimMutation())!;
        await store.applyCanonicalSongReceipt(request, MutationResponse(200, jsonEncode({
          'created': false, 'canonical_song_id': fixtureId(21),
          'song': fixtureSong(fixtureId(21), 2),
        })));
      } else if (authenticationStatus == null) {
        await repository.save(
          repository.prepareCreate(
            entity: LocalEntity.tag,
            entityId: fixtureId(10),
            draft: {'name': '처음 이름'},
            changes: {'name': '처음 이름'},
          ),
        );
        await store.acknowledgeMutation(
          (await store.claimMutation())!,
          fixtureTag(fixtureId(10), '처음 이름', 1),
        );
        await repository.save(
          repository.preparePatch(
            entity: LocalEntity.tag,
            entityId: fixtureId(10),
            baseRevision: 1,
            draft: fixtureTag(fixtureId(10), '이 기기 이름', 1),
            changes: {'name': '이 기기 이름'},
          ),
        );
        await store.deferMutation(
          (await store.claimMutation())!,
          'CONFLICT',
          'REVISION_CONFLICT',
          status: 409,
          serverSnapshot: fixtureTag(fixtureId(10), '서버 이름', 2),
        );
      } else {
        for (final n in [10, 11]) {
          await repository.save(
            repository.prepareCreate(
              entity: LocalEntity.tag,
              entityId: fixtureId(n),
              draft: {'name': '검증 항목 $n'},
              changes: {'name': '검증 항목 $n'},
            ),
          );
        }
      }
      final auth = AuthSession(
        userId: fixtureId(1),
        deviceId: fixtureId(2),
        accessToken: 'synthetic-only',
        refreshToken: 'synthetic-only',
        accessExpiresAt: DateTime.utc(2099),
        refreshExpiresAt: DateTime.utc(2099),
      );
      final controller = SyncController(
        RepositorySyncBackend(repository, transport, () async => auth),
        conflicts: changeOnReview
            ? _ChangingReviewActions(repository, () async {
                // Only this newly-created synthetic run is touched. This hook
                // simulates an incoming server change after the screen reads.
                store.requireActive();
                final paths = await AccountPaths.create(run, fixtureId(1), AppEnvironment.dev);
                final db = AccountDatabase(NativeDatabase(await paths.databaseFile()),
                  userId: fixtureId(1), environment: AppEnvironment.dev);
                try {
                  await db.verifyReady();
                  await db.transaction(() async {
                    store.requireActive();
                    await db.customStatement(
                      "UPDATE metadata_copies SET server_revision=3,server_payload=? WHERE entity_type='SONG' AND entity_id=?",
                      [canonicalJson(fixtureSong(fixtureId(21), 3, note: '뒤에 도착한 서버 메모')), fixtureId(21)],
                    );
                    store.requireActive();
                  });
                } finally { await db.close(); }
              })
            : repository,
      );
      await controller.refresh();
      return SyncVerificationFixture._(manager, store, controller, transport);
    } catch (_) {
      await manager.logout();
      rethrow;
    }
  }

  Future<void> close() async {
    controller.dispose();
    await manager.logout();
  }
}

final class _ChangingReviewActions implements ConflictActions, CanonicalConflictActions {
  _ChangingReviewActions(this.repository, this.advance);
  final LocalRepository repository;
  final Future<void> Function() advance;
  bool changed = false;
  @override
  Future<ConflictReview> review(String opId) => repository.review(opId);
  @override
  Future<void> resolve(ConflictReview review, Map<String, ConflictChoice> choices) => repository.resolve(review, choices);
  @override
  Future<List<CanonicalConflictReview>> canonicalCandidates() => repository.canonicalCandidates();
  @override
  Future<CanonicalConflictReview> reviewCanonical(String intentId) async {
    final result = await repository.reviewCanonical(intentId);
    if (!changed) { changed = true; await advance(); }
    return result;
  }
  @override
  Future<void> resolveCanonical(CanonicalConflictReview review, ConflictChoice choice) => repository.resolveCanonical(review, choice);
}
