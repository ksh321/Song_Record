import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/features/auth/auth_session.dart';

import '../tool/sync_verification_fixture.dart';
import 'change_payload_validation_test.dart' show recordingWire;
import 'metadata_dispatcher_test.dart' show FakeTransport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('two canonical choices can review a held successor after the first re-conflicts', () async {
    final root = await Directory.systemTemp.createTemp('sr-canonical-successor-');
    final fixture = await SyncVerificationFixture.create(root, canonical: true, responseDelay: () async {});
    var store = fixture.store;
    var repo = LocalRepository(store);
    final source = fixtureId(30), target = fixtureId(31);
    Future<Map<String, dynamic>> tables() async =>
        (jsonDecode(await store.recoveryData()) as Map<String, dynamic>)['tables'] as Map<String, dynamic>;
    try {
      await repo.resolveCanonical((await repo.canonicalCandidates()).single, ConflictChoice.server);
      final input = {...fixtureSong(source, 0), 'title': '내 제목'};
      await repo.save(repo.prepareCreate(entity: LocalEntity.song, entityId: source,
        draft: input, changes: {'id': source, 'source_type': 'TJ', 'source_token': 'synthetic'}));
      final create = (await store.claimMutation())!;
      await repo.save(repo.preparePatch(entity: LocalEntity.song, entityId: source,
        baseRevision: 0, draft: {...input, 'note': '후속 메모'}, changes: {'note': '후속 메모'}));
      await store.applyCanonicalSongReceipt(create, MutationResponse(200, jsonEncode({
        'created': false, 'canonical_song_id': target, 'song': fixtureSong(target, 2),
      })));
      final candidates = await repo.canonicalCandidates();
      final first = candidates.singleWhere((c) => (jsonDecode(c.evidence)['intent'] as Map)['kind'] == 'SONG_VALUES');
      final second = candidates.singleWhere((c) => (jsonDecode(c.evidence)['intent'] as Map)['kind'] == 'SONG_MUTATION');
      await repo.resolveCanonical(first, ConflictChoice.local);
      await repo.resolveCanonical(await repo.reviewCanonical(second.intentId), ConflictChoice.local);
      final selected = await tables();
      final intents = (selected['canonical_edit_intents'] as List<dynamic>).cast<Map<String, dynamic>>();
      final firstOp = intents.singleWhere((r) => r['intent_id'] == first.intentId)['resolution_op_id'] as String;
      final secondOp = intents.singleWhere((r) => r['intent_id'] == second.intentId)['resolution_op_id'] as String;
      final claimed = (await store.claimMutation())!;
      expect(claimed.mutation.opId, firstOp);
      await store.deferMutation(claimed, 'CONFLICT', 'REVISION_CONFLICT', status: 409,
        serverSnapshot: fixtureSong(target, 3, note: '서버 후속 메모'));
      await repo.resolve(await repo.review(firstOp), {'note': ConflictChoice.server});
      final firstSuccessor = (await store.claimMutation())!;
      expect(jsonDecode(firstSuccessor.mutation.payload)['title'], '내 제목');
      await store.acknowledgeMutation(firstSuccessor,
        {...fixtureSong(target, 4, note: '서버 후속 메모'), 'title': '내 제목'});
      expect(await store.claimMutation(), isNull);
      expect((await repo.canonicalCandidates()).single.state, 'QUEUED');
      final held = await repo.review(secondOp);
      expect(held.pendingReview, isTrue);
      expect(held.server['revision'], 4);
      final before = await tables();
      await repo.resolve(held, {'note': ConflictChoice.local});
      final after = await tables();
      expect(after['canonical_edit_intents'], before['canonical_edit_intents']);
      expect(after['pending_edit_resolutions'], hasLength(1));
      for (final table in ['local_mutations', 'mutation_wire_requests', 'mutation_retry_controls']) {
        for (final old in before[table] as List<dynamic>) {
          expect((after[table] as List<dynamic>).where((r) => (r as Map)['op_id'] == (old as Map)['op_id']).single, old);
        }
      }
      await fixture.manager.logout();
      store = await fixture.manager.openAccount(fixtureId(1));
      repo = LocalRepository(store);
      final successor = (await store.claimMutation())!;
      expect(successor.mutation.baseRevision, 4);
      expect(jsonDecode(successor.mutation.payload)['note'], '후속 메모');
      await store.deferMutation(successor, 'CONFLICT', 'REVISION_CONFLICT', status: 409,
        serverSnapshot: {...fixtureSong(target, 5, note: '다시 서버 변경'), 'title': '내 제목'});
      await repo.resolve(await repo.review(successor.mutation.opId), {'note': ConflictChoice.local});
      final last = (await store.claimMutation())!;
      await store.acknowledgeMutation(last,
        {...fixtureSong(target, 6, note: '후속 메모'), 'title': '내 제목'});
      expect(await repo.canonicalCandidates(), isEmpty);
      expect(await store.pendingWorkMutations(), isEmpty);
      final resolved = (await tables())['canonical_edit_intents'] as List<dynamic>;
      expect(resolved.cast<Map<String, dynamic>>().singleWhere((r) => r['intent_id'] == second.intentId)['resolution_op_id'], secondOp);
      await fixture.manager.openAccount(fixtureId(70));
      await expectLater(repo.review(secondOp), throwsStateError);
      store = await fixture.manager.openAccount(fixtureId(1));
      expect(await store.canonicalCandidates(), isEmpty);
    } finally {
      await fixture.close();
      expect(root.path.split(Platform.pathSeparator).last, startsWith('sr-canonical-successor-'));
      await root.delete(recursive: true);
    }
  });
  test('canonical choice survives re-conflict, reopen and account switch without losing audio or source evidence', () async {
    final root = await Directory.systemTemp.createTemp('sr-canonical-roundtrip-');
    final fixture = await SyncVerificationFixture.create(root, canonical: true, responseDelay: () async {});
    var store = fixture.store;
    var repo = LocalRepository(store);
    final auth = AuthSession(userId: fixtureId(1), deviceId: fixtureId(2),
      accessToken: 'synthetic', refreshToken: 'unused',
      accessExpiresAt: DateTime.utc(2099), refreshExpiresAt: DateTime.utc(2099));
    try {
      final run = (await root.list().toList()).whereType<Directory>().single;
      final paths = await AccountPaths.create(run, fixtureId(1), AppEnvironment.dev);
      final rec = fixtureId(50);
      final audio = await paths.checkedFile(paths.audioPath(rec));
      final bytes = List<int>.generate(32, (i) => i);
      await audio.writeAsBytes(bytes);
      final draft = <String, dynamic>{...recordingWire('RecordingDraft'),
        'id': rec, 'song_id': fixtureId(21), 'note': '보존할 당시 입력'};
      await store.saveEdit(LocalEdit(opId: fixtureId(51), entity: LocalEntity.recording,
        entityId: rec, operation: LocalOperation.create, baseRevision: 0,
        draft: draft, changes: draft));
      await store.recordFileAndJournal(recordingId: rec, operationId: fixtureId(52),
        state: FilePresence.inputPending, phase: JournalPhase.committed,
        pending: false, checksum: sha256.convert(bytes).toString(), sizeBytes: bytes.length,
        recovery: draft);
      final before = (jsonDecode(await store.recoveryData()) as Map<String, dynamic>)['tables'] as Map<String, dynamic>;
      final journal = await store.readJournal(rec);
      final review = (await repo.canonicalCandidates()).single;
      await repo.resolveCanonical(review, ConflictChoice.local);
      final selected = (await store.pendingWorkMutations()).singleWhere((m) => m.entity == LocalEntity.song);
      final remote = fixtureSong(fixtureId(21), 3, note: '그 뒤 서버 메모');
      final conflict = FakeTransport((request) async {
        expect(request.mutation.opId, selected.opId);
        return MutationResponse(409, jsonEncode({'error': {'code': 'REVISION_CONFLICT',
          'details': {'current_revision': 3, 'current': remote}}}));
      });
      await repo.dispatch(transport: conflict, session: () async => auth, limit: 1);
      expect(conflict.calls, 1);
      expect((await repo.canonicalCandidates()).single.state, 'QUEUED');
      final frozen = (jsonDecode(await store.recoveryData()) as Map<String, dynamic>)['tables'] as Map<String, dynamic>;
      await fixture.manager.logout();
      store = await fixture.manager.openAccount(fixtureId(1));
      repo = LocalRepository(store);
      final retryReview = await repo.review(selected.opId);
      expect(retryReview.server['revision'], 3);
      await repo.resolve(retryReview, {'note': ConflictChoice.local});
      final resolutionTables = (jsonDecode(await store.recoveryData()) as Map<String, dynamic>)['tables'] as Map<String, dynamic>;
      final resolution = (resolutionTables['mutation_conflict_resolutions'] as List<dynamic>).single as Map<String, dynamic>;
      expect(resolution['order_root_op_id'], selected.opId);
      expect(resolution['logical_order'], selected.localOrder);
      final dispatch = await store.dispatchSnapshot();
      final successor = dispatch.pending.singleWhere((m) => m.opId == resolution['replacement_op_id']);
      expect(dispatch.mapping.orderOf(successor), lessThan(selected.localOrder));
      expect((await repo.canonicalCandidates()).single.state, 'QUEUED');
      final ack = FakeTransport((request) async => MutationResponse(200,
        jsonEncode(fixtureSong(fixtureId(21), 4, note: '이 기기 개인 메모'))));
      expect(await repo.dispatch(transport: ack, session: () async => auth, limit: 1), 1);
      expect(await repo.canonicalCandidates(), isEmpty);
      final after = (jsonDecode(await store.recoveryData()) as Map<String, dynamic>)['tables'] as Map<String, dynamic>;
      for (final table in ['song_aliases', 'local_recording_files', 'recording_journals']) {
        expect(after[table], before[table]);
      }
      for (final old in frozen['mutation_wire_requests'] as List<dynamic>) {
        expect((after['mutation_wire_requests'] as List<dynamic>).where((r) => (r as Map)['op_id'] == (old as Map)['op_id']).single, old);
      }
      expect(await store.readJournal(rec), journal);
      expect(await audio.readAsBytes(), bytes);
      final staleRepo = repo;
      final other = await fixture.manager.openAccount(fixtureId(70));
      expect(await other.canonicalCandidates(), isEmpty);
      expect(await other.readMetadata(LocalEntity.recording, rec), isNull);
      await expectLater(staleRepo.reviewCanonical(review.intentId), throwsStateError);
      store = await fixture.manager.openAccount(fixtureId(1));
      expect(await store.canonicalCandidates(), isEmpty);
      expect(await store.readJournal(rec), journal);
      expect(await audio.readAsBytes(), bytes);
    } finally {
      await fixture.close();
      expect(root.path.split(Platform.pathSeparator).last, startsWith('sr-canonical-roundtrip-'));
      await root.delete(recursive: true);
    }
  });
}
