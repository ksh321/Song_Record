import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/conflict_resolution_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/local_repository.dart';

import 'metadata_dispatcher_test.dart' show id, tag;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late LocalRepository repo;
  late QueuedMutation conflict;
  late String local;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sr-conflict-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(id(1));
    repo = LocalRepository(store);
    await repo.save(
      repo.prepareCreate(
        entity: LocalEntity.tag,
        entityId: id(10),
        draft: {'name': 'tag'},
        changes: {'name': 'tag'},
      ),
    );
    await store.acknowledgeMutation(
      (await store.claimMutation())!,
      tag(id(10)),
    );
    await repo.save(
      repo.preparePatch(
        entity: LocalEntity.tag,
        entityId: id(10),
        baseRevision: 1,
        draft: tag(id(10), name: 'local'),
        changes: {'name': 'local'},
      ),
    );
    await store.deferMutation(
      (await store.claimMutation())!,
      'CONFLICT',
      'REVISION_CONFLICT',
      status: 409,
      serverSnapshot: tag(id(10), name: 'remote', revision: 2),
    );
    conflict = (await store.pendingMutations()).single;
    local = (await store.readMetadata(LocalEntity.tag, id(10)))!.localJson!;
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });
  Future<Map<String, dynamic>> tables() async =>
      (jsonDecode(await store.recoveryData()) as Map<String, dynamic>)['tables']
          as Map<String, dynamic>;

  Future<void> resolve({
    ConflictChoice choice = ConflictChoice.local,
    String? newId,
    String? expectedDraft,
  }) => store.resolveMetadataConflict(
    expected: conflict,
    expectedLocalJson: expectedDraft ?? local,
    replacementOpId: choice == ConflictChoice.server ? null : newId ?? id(30),
    choices: {'name': choice},
  );

  Future<AccountDatabase> raw() async {
    final paths = await AccountPaths.create(root, id(1), AppEnvironment.dev);
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: id(1),
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    return db;
  }

  test(
    'late account fence rolls back queue retry history and metadata together',
    () async {
      final before = await tables();
      final audio = File('${root.path}/synthetic-audio.bin');
      await audio.writeAsBytes([1, 2, 3, 4]);
      final db = await raw();
      var checks = 0;
      try {
        await expectLater(
          db.transaction(
            () =>
                ConflictResolutionStore(db, () {
                  if (++checks == 2) {
                    throw StateError('account changed before commit');
                  }
                }).resolve(
                  expected: conflict,
                  expectedLocalJson: local,
                  replacementOpId: id(30),
                  choices: {'name': ConflictChoice.local},
                  now: 123,
                ),
          ),
          throwsStateError,
        );
      } finally {
        await db.close();
      }
      expect(checks, 2);
      expect(await tables(), before);
      expect(await audio.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  for (final mode in ['newer', 'deleted', 'different']) {
    test(
      'changed server baseline $mode rejects stale conflict resolution',
      () async {
        final db = await raw();
        try {
          await db.customStatement(
            'UPDATE metadata_copies SET server_revision=?,server_payload=?,tombstone=? WHERE entity_id=?',
            [
              mode == 'newer' ? 3 : 2,
              jsonEncode(
                tag(id(10), name: 'changed', revision: mode == 'newer' ? 3 : 2),
              ),
              mode == 'deleted' ? 1 : 0,
              id(10),
            ],
          );
        } finally {
          await db.close();
        }
        final before = await tables();
        await expectLater(resolve(), throwsStateError);
        expect(await tables(), before);
      },
    );
  }

  test(
    'resolution preserves original wire and creates one fresh request',
    () async {
      final before = await tables();
      await resolve();
      final after = await tables();
      expect(
        (after['local_mutations'] as List).firstWhere(
          (r) => r['op_id'] == conflict.opId,
        ),
        (before['local_mutations'] as List).firstWhere(
          (r) => r['op_id'] == conflict.opId,
        ),
      );
      expect(after['mutation_wire_requests'], before['mutation_wire_requests']);
      expect(
        (after['mutation_retry_controls'] as List).firstWhere(
          (r) => r['op_id'] == conflict.opId,
        ),
        (before['mutation_retry_controls'] as List).firstWhere(
          (r) => r['op_id'] == conflict.opId,
        ),
      );
      expect(after['mutation_conflict_resolutions'], hasLength(1));
      final request = (await store.claimMutation())!;
      expect(request.mutation.opId, id(30));
      expect(request.attempt, 1);
      expect(jsonDecode(request.body), {'base_revision': 2, 'name': 'local'});
      expect(await store.claimMutation(), isNull);
      await store.acknowledgeMutation(
        request,
        tag(id(10), name: 'normalized', revision: 3),
      );
      expect(
        jsonDecode(
          (await store.readMetadata(LocalEntity.tag, id(10)))!.localJson!,
        )['name'],
        'normalized',
      );
      expect((await store.pendingMutations()).single.state, 'CONFLICT');
      expect(await store.claimMutation(), isNull);
    },
  );
  test(
    'repository review resolves work list while retaining recovery history',
    () async {
      final review = await repo.review(conflict.opId);
      expect(review.localJson, local);
      expect(review.server['name'], 'remote');
      expect((await repo.pendingWork()).single.opId, conflict.opId);
      await repo.resolve(review, {'name': ConflictChoice.server});
      expect(await repo.pendingWork(), isEmpty);
      expect((await repo.pending()).single.opId, conflict.opId);
      await expectLater(repo.review(conflict.opId), throwsStateError);
    },
  );
  test(
    'server choice creates no new request and retains original conflict',
    () async {
      await resolve(choice: ConflictChoice.server);
      expect(await store.claimMutation(), isNull);
      expect((await store.pendingMutations()).single.opId, conflict.opId);
      final copy = (await store.readMetadata(LocalEntity.tag, id(10)))!;
      expect(copy.revision, 2);
      expect(jsonDecode(copy.localJson!)['name'], 'remote');
      final data = await tables();
      expect(
        (data['mutation_conflict_resolutions'] as List)
            .single['replacement_op_id'],
        isNull,
      );
    },
  );
  test(
    'changed local input refuses stale selection without partial writes',
    () async {
      await repo.save(
        repo.preparePatch(
          entity: LocalEntity.tag,
          entityId: id(10),
          baseRevision: 1,
          draft: tag(id(10), name: 'newer'),
          changes: {'name': 'newer'},
        ),
      );
      final before = await tables();
      await expectLater(resolve(), throwsStateError);
      expect(await tables(), before);
    },
  );
  test('confirmed newer draft remains intact and is not sent ahead', () async {
    final younger = repo.preparePatch(
      entity: LocalEntity.tag,
      entityId: id(10),
      baseRevision: 1,
      draft: tag(id(10), name: 'newer'),
      changes: {'name': 'newer'},
    );
    await repo.save(younger);
    final newest = (await store.readMetadata(
      LocalEntity.tag,
      id(10),
    ))!.localJson!;
    await resolve(expectedDraft: newest);
    final request = (await store.claimMutation())!;
    expect(request.mutation.opId, id(30));
    await store.acknowledgeMutation(
      request,
      tag(id(10), name: 'local', revision: 3),
    );
    expect(
      (await store.readMetadata(LocalEntity.tag, id(10)))!.localJson,
      newest,
    );
    expect(await store.claimMutation(), isNull);
    expect(
      (await store.pendingMutations())
          .firstWhere((r) => r.opId == younger.opId)
          .attemptCount,
      0,
    );
  });
  test('duplicate application rejects without another queue entry', () async {
    await resolve();
    final before = await tables();
    await expectLater(resolve(), throwsStateError);
    expect(await tables(), before);
  });
  test('colliding operation ID rolls back all writes', () async {
    final before = await tables();
    final used = (before['local_mutations'] as List).first['op_id'] as String;
    await expectLater(resolve(newId: used), throwsA(isA<Exception>()));
    expect(await tables(), before);
  });
  test(
    'account change invalidates resolution and preserves previous account',
    () async {
      final before = await tables();
      await manager.openAccount(id(2));
      await expectLater(resolve(), throwsStateError);
      store = await manager.openAccount(id(1));
      expect(await tables(), before);
    },
  );
}
