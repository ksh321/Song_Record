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
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'metadata_dispatcher_test.dart' show id, tag, FakeTransport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late DateTime now;
  late AccountStoreManager manager;
  late AccountStore store;
  late LocalRepository repo;
  Future<AuthSession> session() async => AuthSession(
    userId: id(1),
    deviceId: id(2),
    accessToken: 'test',
    refreshToken: 'test',
    accessExpiresAt: now.add(const Duration(hours: 1)),
    refreshExpiresAt: now.add(const Duration(days: 1)),
  );
  Future<LocalEdit> create(int n) async {
    final edit = repo.prepareCreate(
      entity: LocalEntity.tag,
      entityId: id(n),
      draft: {'name': 'tag'},
      changes: {'name': 'tag'},
    );
    await repo.save(edit);
    return edit;
  }

  setUp(() async {
    now = DateTime.utc(2026, 9, 29);
    root = await Directory.systemTemp.createTemp('sr-retry-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
      clock: () => now,
    );
    store = await manager.openAccount(id(1));
    repo = LocalRepository(store);
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });

  test('same frozen request retries 1 5 15 minutes and consumes only three automatic claims', () async {
    final edit = await create(10);
    final requests = <MutationRequest>[];
    final transport = FakeTransport((r) async {
      requests.add(r);
      throw const MutationNetworkFailure();
    });
    await repo.dispatch(transport: transport, session: session);
    for (final minutes in [1, 5, 15]) {
      final due = now.add(Duration(minutes: minutes));
      expect(await repo.nextAutomaticRetryAt(), due);
      now = due.subtract(const Duration(milliseconds: 1));
      expect(await repo.dispatch(transport: transport, session: session), 0);
      now = due;
      await repo.dispatch(transport: transport, session: session);
    }
    expect(requests.length, 4);
    expect(requests.map((r) => r.attempt), [1, 2, 3, 4]);
    expect(requests.map((r) => r.hash).toSet().length, 1);
    expect(requests.map((r) => r.body).toSet(), {edit.changesJson});
    expect(requests.map((r) => r.mutation.opId).toSet(), {edit.opId});
    final status = (await repo.retryStatus(edit.opId))!;
    expect(status.automaticRetriesClaimed, 3);
    expect(status.mode, 'MANUAL_REQUIRED');
    expect(await repo.nextAutomaticRetryAt(), isNull);
    now = now.add(const Duration(days: 1));
    await repo.dispatch(transport: transport, session: session);
    expect(requests.length, 4);
    expect(await repo.retryMutation(edit.opId, expectedAttempt: 3), isFalse);
    expect(await repo.retryMutation(edit.opId, expectedAttempt: 4), isTrue);
    expect(await repo.retryMutation(edit.opId, expectedAttempt: 4), isFalse);
    await repo.dispatch(transport: transport, session: session);
    expect(requests.length, 5);
    expect((await repo.retryStatus(edit.opId))!.automaticRetriesClaimed, 3);
    expect((await repo.retryStatus(edit.opId))!.mode, 'MANUAL_REQUIRED');
  });

  test(
    'reopening recovers a consumed attempt once without moving its deadline',
    () async {
      final edit = await create(10);
      final request = (await store.claimMutation())!;
      expect(request.attempt, 1);
      store = await manager.openAccount(id(1));
      repo = LocalRepository(store);
      final due = now.add(const Duration(minutes: 1));
      expect(await repo.nextAutomaticRetryAt(), due);
      now = now.add(const Duration(seconds: 30));
      store = await manager.openAccount(id(1));
      repo = LocalRepository(store);
      expect(await repo.nextAutomaticRetryAt(), due);
      now = due;
      final retry = (await store.claimMutation())!;
      expect(retry.hash, request.hash);
      expect(retry.attempt, 2);
      store = await manager.openAccount(id(1));
      repo = LocalRepository(store);
      expect((await repo.retryStatus(edit.opId))!.automaticRetriesClaimed, 1);
      expect(
        await repo.nextAutomaticRetryAt(),
        now.add(const Duration(minutes: 5)),
      );
    },
  );

  test(
    'concurrent retry claims spend one budget unit and ACK atomically',
    () async {
      final edit = await create(10);
      await repo.dispatch(
        transport: FakeTransport(
          (_) async => const MutationResponse(503, '{}'),
        ),
        session: session,
      );
      now = now.add(const Duration(minutes: 1));
      final claims = await Future.wait([
        store.claimMutation(),
        store.claimMutation(),
      ]);
      final request = claims.whereType<MutationRequest>().single;
      expect(request.attempt, 2);
      expect((await repo.retryStatus(edit.opId))!.automaticRetriesClaimed, 1);
      expect(
        await store.acknowledgeMutation(request, tag(edit.entityId)),
        isTrue,
      );
      expect(await repo.pending(), isEmpty);
      expect((await repo.retryStatus(edit.opId))!.nextAttemptAt, isNull);
      expect(await store.readCursor(), isNull);
    },
  );

  test(
    'frozen PATCH retries after baseline advances without rewriting its body',
    () async {
      final edit = await create(10);
      await repo.dispatch(
        transport: FakeTransport(
          (_) async => MutationResponse(201, jsonEncode(tag(edit.entityId))),
        ),
        session: session,
      );
      final patch = repo.preparePatch(
        entity: LocalEntity.tag,
        entityId: edit.entityId,
        baseRevision: 1,
        draft: {'name': 'changed'},
        changes: {'name': 'changed'},
      );
      await repo.save(patch);
      final requests = <MutationRequest>[];
      final transport = FakeTransport((r) async {
        requests.add(r);
        throw const MutationNetworkFailure();
      });
      await repo.dispatch(transport: transport, session: session);
      final paths = await AccountPaths.create(root, id(1), AppEnvironment.dev);
      final db = sqlite.sqlite3.open((await paths.databaseFile()).path);
      db.execute(
        "UPDATE metadata_copies SET server_revision=2 WHERE entity_type='TAG'",
      );
      db.close();
      now = now.add(const Duration(minutes: 1));
      expect(await repo.nextAutomaticRetryAt(), now);
      await repo.dispatch(transport: transport, session: session);
      expect(requests.length, 2);
      expect(requests.last.hash, requests.first.hash);
      expect(requests.last.body, patch.changesJson);
      expect(requests.last.mutation.baseRevision, 1);
      expect((await repo.read(LocalEntity.tag, edit.entityId))!.revision, 2);
    },
  );

  for (final (deleted, currentRevision) in [(false, 3), (true, 3), (true, 2)]) {
    test(
      'old replay ACK preserves ${deleted ? 'tombstone' : 'metadata'} revision $currentRevision',
      () async {
        final edit = await create(10);
        await repo.dispatch(
          transport: FakeTransport(
            (_) async => MutationResponse(201, jsonEncode(tag(edit.entityId))),
          ),
          session: session,
        );
        final patch = repo.preparePatch(
          entity: LocalEntity.tag,
          entityId: edit.entityId,
          baseRevision: 1,
          draft: {'name': 'changed'},
          changes: {'name': 'changed'},
        );
        await repo.save(patch);
        await repo.dispatch(
          transport: FakeTransport(
            (_) async => throw const MutationNetworkFailure(),
          ),
          session: session,
        );
        final paths = await AccountPaths.create(
          root,
          id(1),
          AppEnvironment.dev,
        );
        final db = sqlite.sqlite3.open((await paths.databaseFile()).path);
        final latest = canonicalJson(
          tag(edit.entityId, name: 'newest-server', revision: currentRevision),
        );
        final local = canonicalJson({'name': 'latest-local-input'});
        db.execute(
          "UPDATE metadata_copies SET server_revision=?,server_payload=?,local_payload=?,tombstone=? WHERE entity_type='TAG'",
          [currentRevision, latest, local, deleted ? 1 : 0],
        );
        db.close();
        now = now.add(const Duration(minutes: 1));
        final replay = FakeTransport((r) async {
          expect(r.mutation.opId, patch.opId);
          expect(r.body, patch.changesJson);
          return MutationResponse(
            200,
            jsonEncode(tag(edit.entityId, name: 'changed', revision: 2)),
          );
        });
        expect(await repo.dispatch(transport: replay, session: session), 1);
        expect(await repo.pending(), isEmpty);
        final copy = (await repo.read(LocalEntity.tag, edit.entityId))!;
        expect(copy.revision, currentRevision);
        expect(copy.serverJson, latest);
        expect(copy.localJson, local);
        expect(copy.tombstone, deleted);
        expect((await repo.retryStatus(patch.opId))!.queueState, 'ACKED');
        expect(await repo.nextAutomaticRetryAt(), isNull);
      },
    );
  }

  test(
    'claim transaction rolls back both attempt and budget on storage failure',
    () async {
      final edit = await create(10);
      await repo.dispatch(
        transport: FakeTransport(
          (_) async => throw const MutationNetworkFailure(),
        ),
        session: session,
      );
      now = now.add(const Duration(minutes: 1));
      final paths = await AccountPaths.create(root, id(1), AppEnvironment.dev);
      final db = sqlite.sqlite3.open((await paths.databaseFile()).path);
      try {
        db.execute(
          "CREATE TRIGGER reject_budget BEFORE UPDATE ON mutation_retry_controls WHEN NEW.automatic_retries_claimed>0 BEGIN SELECT RAISE(ABORT,'injected'); END;",
        );
        await expectLater(store.claimMutation(), throwsA(anything));
        final status = (await repo.retryStatus(edit.opId))!;
        expect(status.attemptCount, 1);
        expect(status.automaticRetriesClaimed, 0);
        expect(status.queueState, 'RETRY');
        db.execute('DROP TRIGGER reject_budget');
        expect((await store.claimMutation())!.attempt, 2);
        expect(
          () => db.execute(
            'UPDATE mutation_retry_controls SET automatic_retries_claimed=0',
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
      } finally {
        db.close();
      }
    },
  );

  test('blocked authentication never consumes automatic budget after time or reopen', () async {
    final edit = await create(10);
    final transport = FakeTransport(
      (_) async => const MutationResponse(401, '{}'),
    );
    await repo.dispatch(transport: transport, session: session);
    now = now.add(const Duration(days: 2));
    store = await manager.openAccount(id(1));
    repo = LocalRepository(store);
    await repo.dispatch(transport: transport, session: session);
    expect(transport.calls, 1);
    expect((await repo.retryStatus(edit.opId))!.mode, 'BLOCKED');
    expect((await repo.retryStatus(edit.opId))!.automaticRetriesClaimed, 0);
    expect(await repo.nextAutomaticRetryAt(), isNull);
    // Explicit user retry after fixing authentication permits one send only.
    expect(await repo.retryMutation(edit.opId, expectedAttempt: 1), isTrue);
    final success = FakeTransport(
      (_) async => MutationResponse(201, jsonEncode(tag(edit.entityId))),
    );
    expect(await repo.dispatch(transport: success, session: session), 1);
    expect((await repo.retryStatus(edit.opId))!.automaticRetriesClaimed, 0);
  });

  test('v2 migration preserves frozen requests and never replenishes unknown budgets', () async {
    final owner = id(40);
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    final file = await paths.databaseFile();
    final old = sqlite.sqlite3.open(file.path);
    old.execute(await File('test/fixtures/local_schema_v2.sql').readAsString());
    old.execute('PRAGMA user_version=2');
    old.execute("INSERT INTO local_account VALUES(1,?,'dev',1)", [owner]);
    old.execute(
      'INSERT INTO sync_cursors(singleton,user_id,updated_at) VALUES(1,?,1)',
      [owner],
    );
    final body = canonicalJson({'id': id(50), 'name': 'old'});
    final mutation = QueuedMutation(
      opId: id(60),
      localOrder: 1,
      entity: LocalEntity.tag,
      entityId: id(50),
      operation: LocalOperation.create,
      state: 'SENDING',
      baseRevision: 0,
      payload: body,
      attemptCount: 4,
    );
    final frozen = MutationRequest.prepare(mutation)!;
    old.execute(
      "INSERT INTO metadata_copies(user_id,entity_type,entity_id,local_payload,updated_at) VALUES(?,'TAG',?,?,1)",
      [owner, id(50), body],
    );
    old.execute(
      "INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,queue_state,attempt_count,created_at,updated_at) VALUES(?,?,'TAG',?,'CREATE',0,?,?,'SENDING',4,1,1)",
      [id(60), owner, id(50), body, 'a' * 64],
    );
    old.execute('INSERT INTO mutation_wire_requests VALUES(?,?,?,?,?,?)', [
      id(60),
      MutationRequest.contract,
      frozen.method,
      frozen.path,
      frozen.body,
      frozen.hash,
    ]);
    old.close();
    final audio = await paths.checkedFile(paths.audioPath(id(70)));
    await audio.writeAsBytes([4, 8, 12]);
    final upgraded = await manager.openAccount(owner);
    final status = (await upgraded.retryStatus(id(60)))!;
    expect(status.automaticRetriesClaimed, isNull);
    expect(status.mode, 'MANUAL_REQUIRED');
    expect(status.attemptCount, 4);
    expect(await upgraded.claimMutation(), isNull);
    expect(await upgraded.retryMutation(id(60), expectedAttempt: 4), isTrue);
    final request = (await upgraded.claimMutation())!;
    expect(request.hash, frozen.hash);
    expect(request.body, body);
    expect(request.attempt, 5);
    expect(
      (await upgraded.retryStatus(id(60)))!.automaticRetriesClaimed,
      isNull,
    );
    expect(await audio.readAsBytes(), [4, 8, 12]);
  });

  test(
    'account change fences retry APIs and keeps account data isolated',
    () async {
      final edit = await create(10);
      await repo.dispatch(
        transport: FakeTransport(
          (_) async => throw const MutationNetworkFailure(),
        ),
        session: session,
      );
      final old = repo;
      final other = LocalRepository(await manager.openAccount(id(3)));
      expect(await other.retryStatus(edit.opId), isNull);
      await expectLater(
        old.retryMutation(edit.opId, expectedAttempt: 1),
        throwsStateError,
      );
      store = await manager.openAccount(id(1));
      repo = LocalRepository(store);
      final recovery = jsonDecode(await store.recoveryData());
      expect(recovery['tables']['mutation_retry_controls'], hasLength(1));
      expect((await repo.retryStatus(edit.opId))!.attemptCount, 1);
    },
  );
}
