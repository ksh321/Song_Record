import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
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
      if (authenticationStatus == null) {
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
        conflicts: repository,
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
