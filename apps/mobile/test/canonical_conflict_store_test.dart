import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/canonical_conflict_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';

import '../tool/sync_verification_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SyncVerificationFixture fixture;
  late AccountStore store;
  late LocalRepository repo;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sr-canonical-choice-');
    fixture = await SyncVerificationFixture.create(root, canonical: true, responseDelay: () async {});
    store = fixture.store;
    repo = LocalRepository(store);
  });
  tearDown(() async { await fixture.close(); await root.delete(recursive: true); });
  Future<Map<String, dynamic>> tables() async =>
    (jsonDecode(await store.recoveryData()) as Map<String, dynamic>)['tables'] as Map<String, dynamic>;
  Future<AccountDatabase> raw() async {
    final run = (await root.list().toList()).whereType<Directory>().single;
    final paths = await AccountPaths.create(run, fixtureId(1), AppEnvironment.dev);
    final db = AccountDatabase(NativeDatabase(await paths.databaseFile()), userId: fixtureId(1), environment: AppEnvironment.dev);
    await db.verifyReady();
    return db;
  }
  test('server choice resolves without a request or invented ACK; repeated click is rejected', () async {
    final before = await tables();
    final review = (await repo.canonicalCandidates()).single;
    expect(review.canChoose, isTrue);
    await repo.resolveCanonical(review, ConflictChoice.server);
    final after = await tables();
    expect(after['local_mutations'], before['local_mutations']);
    expect(after['song_aliases'], before['song_aliases']);
    expect(await repo.canonicalCandidates(), isEmpty);
    await expectLater(repo.resolveCanonical(review, ConflictChoice.local), throwsStateError);
    expect(await tables(), after);
  });
  test('local choice retains immutable request and waits for owned ACK', () async {
    final before = await tables();
    await repo.resolveCanonical((await repo.canonicalCandidates()).single, ConflictChoice.local);
    final queued = (await repo.canonicalCandidates()).single;
    expect(queued.state, 'QUEUED');
    final pending = (await store.pendingWorkMutations()).single;
    expect(pending.entityId, fixtureId(21));
    expect(pending.baseRevision, 2);
    final request = (await store.claimMutation())!;
    expect(jsonDecode(request.body)['note'], '이 기기 개인 메모');
    expect((await repo.canonicalCandidates()).single.state, 'QUEUED');
    await store.acknowledgeMutation(request, fixtureSong(fixtureId(21), 3, note: '이 기기 개인 메모'));
    expect(await repo.canonicalCandidates(), isEmpty);
    final after = await tables();
    expect((after['local_mutations'] as List).first, (before['local_mutations'] as List).first);
    expect(after['song_aliases'], before['song_aliases']);
    expect(jsonDecode((await store.readMetadata(LocalEntity.song, fixtureId(20)))!.localJson!)['note'], '이 기기 개인 메모');
  });
  test('server change and later queue input invalidate an open choice', () async {
    final review = (await repo.canonicalCandidates()).single;
    await repo.save(repo.preparePatch(entity: LocalEntity.song, entityId: fixtureId(21), baseRevision: 2,
      draft: fixtureSong(fixtureId(21), 2, note: 'later draft'), changes: {'note': 'later draft'}));
    final before = await tables();
    await expectLater(repo.resolveCanonical(review, ConflictChoice.local), throwsStateError);
    expect(await tables(), before);
  });
  test('independent canonical draft survives choosing and acknowledging source values', () async {
    final db = await raw();
    final privateDraft = canonicalJson(fixtureSong(fixtureId(21), 2, note: 'independent canonical input'));
    try {
      await db.customStatement("UPDATE metadata_copies SET local_payload=? WHERE entity_type='SONG' AND entity_id=?", [privateDraft, fixtureId(21)]);
    } finally { await db.close(); }
    await repo.resolveCanonical((await repo.canonicalCandidates()).single, ConflictChoice.local);
    final request = (await store.claimMutation())!;
    await store.acknowledgeMutation(request, fixtureSong(fixtureId(21), 3, note: '이 기기 개인 메모'));
    final copy = (await store.readMetadata(LocalEntity.song, fixtureId(21)))!;
    expect(copy.localJson, privateDraft);
    expect(jsonDecode(copy.serverJson!)['note'], '이 기기 개인 메모');
    expect(await repo.canonicalCandidates(), isEmpty);
  });
  for (final mode in ['sql', 'lease']) {
    test('late $mode failure rolls back choice queue and proof', () async {
      final review = (await repo.canonicalCandidates()).single;
      final before = await tables();
      final db = await raw();
      try {
        if (mode == 'sql') {
          await db.customStatement("CREATE TEMP TRIGGER reject_choice BEFORE UPDATE ON canonical_edit_intents BEGIN SELECT RAISE(ABORT, 'injected'); END");
        }
        var calls = 0;
        await expectLater(db.transaction(() => CanonicalConflictStore(db, () {
          if (mode == 'lease' && ++calls == 3) throw StateError('lost lease');
        }).resolve(review, ConflictChoice.local, fixtureId(99), 1)), throwsA(anything));
      } finally { await db.close(); }
      expect(await tables(), before);
    });
  }
  test('held source PATCH is retired with proof while its wire and row remain unchanged', () async {
    // A second mapping captures a real pending source PATCH, not a fabricated 409.
    final source = fixtureId(30), target = fixtureId(31);
    await repo.save(repo.prepareCreate(entity: LocalEntity.song, entityId: source,
      draft: fixtureSong(source, 0), changes: {'id': source, 'source_type': 'TJ', 'source_token': 'synthetic'}));
    final create = (await store.claimMutation())!;
    await repo.save(repo.preparePatch(entity: LocalEntity.song, entityId: source, baseRevision: 0,
      draft: fixtureSong(source, 0, note: 'held'), changes: {'note': 'held'}));
    await store.applyCanonicalSongReceipt(create, MutationResponse(200, jsonEncode({
      'created': false, 'canonical_song_id': target, 'song': fixtureSong(target, 2),
    })));
    final original = (await store.pendingMutations()).single;
    final candidates = await repo.canonicalCandidates();
    final held = candidates.singleWhere((r) => (jsonDecode(r.evidence)['intent'] as Map)['kind'] == 'SONG_MUTATION');
    expect(held.canChoose, isTrue);
    await repo.resolveCanonical(held, ConflictChoice.local);
    final work = await store.pendingWorkMutations();
    expect(work.any((m) => m.opId == original.opId), isFalse);
    final saved = (await store.pendingMutations()).firstWhere((m) => m.opId == original.opId);
    expect(saved.payload, original.payload);
    expect(saved.basePayload, original.basePayload);
    expect(saved.attemptCount, original.attemptCount);
    expect((await store.claimMutation())!.mutation.entityId, target);
  });
}
