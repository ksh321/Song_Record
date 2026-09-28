import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart'
    show AccountDatabase;
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';

String uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  final owner = uuid(1);
  AccountStoreManager makeManager() => AccountStoreManager(
    environment: AppEnvironment.dev,
    directory: () async => root,
    temporaryDirectory: () async => root,
  );
  Future<AccountDatabase> raw() async {
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    return db;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('song-record-repository-');
    manager = makeManager();
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });

  test('prepared create is immutable and survives a new manager', () async {
    var repo = LocalRepository(await manager.openAccount(owner));
    final draft = <String, Object?>{'title': 'before'};
    final command = repo.prepareCreate(
      entity: LocalEntity.song,
      draft: draft,
      changes: draft,
    );
    expect(command.entityId, matches(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ));
    expect(command.opId, isNot(command.entityId));
    draft['title'] = 'caller changed';
    await repo.save(command);
    await manager.logout();
    manager = makeManager();
    repo = LocalRepository(await manager.openAccount(owner));
    final queued = (await repo.pending()).single;
    expect(queued.opId, command.opId);
    expect(queued.entity, LocalEntity.song);
    expect(queued.entityId, command.entityId);
    expect(queued.operation, LocalOperation.create);
    expect(queued.baseRevision, 0);
    expect(queued.state, 'PENDING');
    expect(queued.attemptCount, 0);
    expect(jsonDecode(queued.payload), {'id': command.entityId, 'title': 'before'});
    await repo.save(command);
    expect(await repo.pending(), hasLength(1));
    expect((await repo.read(LocalEntity.song, command.entityId))!.localJson,
        contains('before'));
  });

  test('offline edits retain each intent and old retry cannot rewind draft', () async {
    final repo = LocalRepository(await manager.openAccount(owner));
    final create = repo.prepareCreate(
      entity: LocalEntity.recording,
      draft: {'note': 'first'},
      changes: {'metadata_state': 'DRAFT', 'note': 'first'},
    );
    await repo.save(create);
    for (final note in ['second', 'third']) {
      await repo.save(repo.preparePatch(
        entity: LocalEntity.recording,
        entityId: create.entityId,
        baseRevision: 0,
        draft: {'note': note},
        changes: {'note': note},
      ));
    }
    await repo.save(create);
    expect(await repo.pending(), hasLength(3));
    expect((await repo.pending()).map((e) => e.opId).toSet(), hasLength(3));
    expect((await repo.read(LocalEntity.recording, create.entityId))!.localJson,
        contains('third'));
  });

  test('server baseline and patch target are persisted across reopening', () async {
    await manager.openAccount(owner);
    await manager.logout();
    final db = await raw();
    await db.customStatement(
      'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,updated_at) VALUES(?,?,?,7,?,1)',
      [owner, 'SONG', uuid(10), '{"title":"server"}'],
    );
    await db.close();
    var repo = LocalRepository(await manager.openAccount(owner));
    final patch = repo.preparePatch(
      entity: LocalEntity.song,
      entityId: uuid(10),
      baseRevision: 7,
      draft: {'title': 'local'},
      changes: {'title': 'local'},
    );
    await repo.save(patch);
    await manager.logout();
    manager = makeManager();
    repo = LocalRepository(await manager.openAccount(owner));
    final queued = (await repo.pending()).single;
    expect(queued.operation, LocalOperation.patch);
    expect(queued.entityId, uuid(10));
    expect(queued.baseRevision, 7);
    expect(jsonDecode(queued.basePayload!), {'title': 'server'});
    expect(jsonDecode(queued.payload), {'base_revision': 7, 'title': 'local'});
    expect((await repo.read(LocalEntity.song, uuid(10)))!.revision, 7);
  });

  test('queue write failure rolls back draft and same command can retry', () async {
    await manager.openAccount(owner);
    await manager.logout();
    var db = await raw();
    await db.customStatement(
      "CREATE TRIGGER fail_repository_queue BEFORE INSERT ON local_mutations BEGIN SELECT RAISE(ABORT, 'repository failure'); END",
    );
    await db.close();
    var repo = LocalRepository(await manager.openAccount(owner));
    final command = repo.prepareCreate(
      entity: LocalEntity.tag,
      draft: {'name': 'test'},
      changes: {'name': 'test'},
    );
    await expectLater(repo.save(command), throwsA(isA<DriftRemoteException>()));
    expect(await repo.read(LocalEntity.tag, command.entityId), isNull);
    expect(await repo.pending(), isEmpty);
    await manager.logout();
    db = await raw();
    await db.customStatement('DROP TRIGGER fail_repository_queue');
    await db.close();
    repo = LocalRepository(await manager.openAccount(owner));
    await repo.save(command);
    expect((await repo.pending()).single.opId, command.opId);
  });

  test('expired account repository cannot access another account', () async {
    final a = LocalRepository(await manager.openAccount(owner));
    final command = a.prepareCreate(
      entity: LocalEntity.song,
      entityId: uuid(20),
      draft: {'title': 'A'},
      changes: {'title': 'A'},
    );
    await a.save(command);
    final b = LocalRepository(await manager.openAccount(uuid(2)));
    expect(await b.read(LocalEntity.song, uuid(20)), isNull);
    expect(await b.pending(), isEmpty);
    await expectLater(a.save(command), throwsStateError);
    await expectLater(a.pending(), throwsStateError);
  });

  test('inconsistent identity and stale server revision write nothing', () async {
    final repo = LocalRepository(await manager.openAccount(owner));
    expect(() => repo.prepareCreate(
      entity: LocalEntity.song,
      entityId: uuid(10),
      draft: {'id': uuid(11)},
      changes: {},
    ), throwsArgumentError);
    expect(() => repo.prepareCreate(
      entity: LocalEntity.song,
      draft: {},
      changes: {'user_id': owner},
    ), throwsArgumentError);
    final patch = repo.preparePatch(
      entity: LocalEntity.song,
      entityId: uuid(10),
      baseRevision: 9,
      draft: {'title': 'local'},
      changes: {'title': 'local'},
    );
    await expectLater(repo.save(patch), throwsStateError);
    expect(await repo.pending(), isEmpty);
    expect(await repo.read(LocalEntity.song, uuid(10)), isNull);
  });
}
