import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/conflict_eligibility.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/database/mapping_eligibility.dart';
import 'package:song_record/core/sync/dependency_planner.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  const owner = '11111111-1111-4111-8111-111111111111';
  const target = '22222222-2222-4222-8222-222222222222';
  const original = '33333333-3333-4333-8333-333333333333';
  const replacement = '44444444-4444-4444-8444-444444444444';
  late AccountDatabase db;
  String snapshot(int revision) =>
      jsonEncode({'id': target, 'revision': revision, 'name': 'server'});
  setUp(() async {
    db = AccountDatabase(
      NativeDatabase.memory(),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    await db.customStatement(
      "INSERT INTO metadata_copies VALUES(?,'TAG',?,1,?,'{\"name\":\"local\"}',0,0)",
      [owner, target, snapshot(1)],
    );
    await db.customStatement(
      '''INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,
      operation,base_revision,base_payload,payload,request_hash,queue_state,attempt_count,server_response,created_at,updated_at)
      VALUES(?,?,'TAG',?,'PATCH',1,?,?,?,'CONFLICT',1,?,0,0)''',
      [
        original,
        owner,
        target,
        snapshot(1),
        jsonEncode({'base_revision': 1, 'name': 'local'}),
        'a' * 64,
        jsonEncode({
          'status': 409,
          'code': 'REVISION_CONFLICT',
          'current': jsonDecode(snapshot(2)),
        }),
      ],
    );
    await db.customStatement(
      '''INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,
      operation,base_revision,base_payload,payload,request_hash,created_at,updated_at)
      VALUES(?,?,'TAG',?,'PATCH',2,?,?,?,0,0)''',
      [
        replacement,
        owner,
        target,
        snapshot(2),
        jsonEncode({'base_revision': 2, 'name': 'local'}),
        'b' * 64,
      ],
    );
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> resolution({
    String? replace = replacement,
    String user = owner,
    int attempt = 1,
    int revision = 2,
    String? proof,
    String choices = '{"name":"LOCAL"}',
    String root = original,
    int order = 1,
  }) => db.customStatement(
    'INSERT INTO mutation_conflict_resolutions VALUES(?,?,?,?,?,?,?,?,?,0)',
    [
      original,
      user,
      replace,
      attempt,
      revision,
      proof ?? snapshot(revision),
      choices,
      root,
      order,
    ],
  );
  Future<List<Map<String, Object?>>> originals() async =>
      (await db
              .customSelect(
                'SELECT rowid AS local_order,* FROM local_mutations ORDER BY rowid',
              )
              .get())
          .map((r) => r.data)
          .toList();
  final rejected = throwsA(isA<sqlite.SqliteException>());

  Future<DispatchPlan> plan(MappingEligibility mapping, int revision) async {
    final rows = await originals();
    return const DependencyPlanner().plan(
      DispatchSnapshot(
        pending: [
          for (final row in rows)
            QueuedMutation(
              opId: row['op_id']! as String,
              localOrder: row['local_order']! as int,
              entity: LocalEntity.tag,
              entityId: row['entity_id']! as String,
              operation: LocalOperation.patch,
              state: row['queue_state']! as String,
              baseRevision: row['base_revision']! as int,
              payload: row['payload']! as String,
              attemptCount: row['attempt_count']! as int,
            ),
        ],
        baselines: {
          LocalTarget(LocalEntity.tag, target): ServerBaseline(
            revision: revision,
            tombstone: false,
          ),
        },
        mapping: mapping,
      ),
    );
  }

  test(
    'resolved original is retained but only replacement can dispatch',
    () async {
      final before = await originals();
      expect((await plan(await readMappingEligibility(db), 2)).ready, isEmpty);
      await resolution();
      final mapping = await readMappingEligibility(db);
      expect(mapping.superseded, {original});
      expect(mapping.logicalOrders[replacement], 1);
      expect((await plan(mapping, 2)).ready.map((r) => r.opId), [replacement]);
      expect(await originals(), before);
    },
  );

  test(
    'later replacement retains first position ahead of younger edits',
    () async {
      const younger = '55555555-5555-4555-8555-555555555555';
      const last = '66666666-6666-4666-8666-666666666666';
      await resolution();
      Future<void> add(String id) => db.customStatement(
        '''
      INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,
      base_revision,base_payload,payload,request_hash,created_at,updated_at)
      VALUES(?,?,'TAG',?,'PATCH',3,?,?,?,0,0)''',
        [
          id,
          owner,
          target,
          snapshot(3),
          '{"base_revision":3,"name":"next"}',
          'c' * 64,
        ],
      );
      await add(younger);
      await db.customStatement(
        "UPDATE local_mutations SET queue_state='CONFLICT',attempt_count=1,server_response=? WHERE op_id=?",
        [
          jsonEncode({
            'status': 409,
            'code': 'REVISION_CONFLICT',
            'current': jsonDecode(snapshot(3)),
          }),
          replacement,
        ],
      );
      await add(last);
      await db.customStatement(
        'INSERT INTO mutation_conflict_resolutions VALUES(?,?,?,1,3,?,?,?,1,0)',
        [replacement, owner, last, snapshot(3), '{}', original],
      );
      final mapping = await readMappingEligibility(db);
      final result = await plan(mapping, 3);
      expect(mapping.superseded, {original, replacement});
      expect(mapping.logicalOrders[last], 1);
      expect(result.ready.map((r) => r.opId), [last]);
      expect(
        result.waiting[younger]?.reason,
        DispatchWaitReason.earlierMutation,
      );
    },
  );

  test(
    'server-only resolution releases later edits without fake acknowledgement',
    () async {
      await resolution(replace: null, choices: '{"name":"SERVER"}');
      final mapping = await readMappingEligibility(db);
      expect(mapping.superseded, {original});
      expect(mapping.logicalOrders, isEmpty);
      expect((await plan(mapping, 2)).ready.map((r) => r.opId), [replacement]);
      expect((await originals()).first['queue_state'], 'CONFLICT');
    },
  );

  test(
    'changed conflict evidence quarantines target and preserves rows',
    () async {
      await resolution();
      await db.customStatement(
        "UPDATE local_mutations SET queue_state='FAILED' WHERE op_id=?",
        [original],
      );
      final before = await originals();
      final mapping = await readMappingEligibility(db);
      expect(mapping.blocked, containsAll([original, replacement]));
      expect((await plan(mapping, 2)).ready, isEmpty);
      expect(await originals(), before);
    },
  );

  test(
    'existing mapping hold cannot be bypassed by conflict history',
    () async {
      await resolution();
      final mapping = await applyConflictEligibility(
        db,
        MappingEligibility(
          blocked: {original},
          superseded: {},
          logicalOrders: {},
          groups: {},
        ),
      );
      expect(mapping.blocked, containsAll([original, replacement]));
      expect((await plan(mapping, 2)).ready, isEmpty);
    },
  );

  test(
    'separate resolution retains original conflict and every request field',
    () async {
      final before = await originals();
      await resolution();
      expect(await originals(), before);
      final row =
          (await db
                  .customSelect('SELECT * FROM mutation_conflict_resolutions')
                  .getSingle())
              .data;
      expect(row['original_op_id'], original);
      expect(row['replacement_op_id'], replacement);
      expect(row['logical_order'], 1);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
  test(
    'resolution without a new request retains explicit server choice',
    () async {
      await resolution(replace: null, choices: '{"name":"SERVER"}');
      expect(
        (await db
                .customSelect(
                  'SELECT replacement_op_id FROM mutation_conflict_resolutions',
                )
                .getSingle())
            .data['replacement_op_id'],
        isNull,
      );
      expect(await originals(), hasLength(2));
    },
  );
  test(
    'resolution evidence cannot update delete replace or retry original',
    () async {
      final before = await originals();
      await resolution();
      for (final sql in [
        "UPDATE mutation_conflict_resolutions SET choices='{}'",
        'DELETE FROM mutation_conflict_resolutions',
        'INSERT OR REPLACE INTO mutation_conflict_resolutions SELECT * FROM mutation_conflict_resolutions',
        "UPDATE local_mutations SET attempt_count=2 WHERE op_id='$original'",
      ]) {
        await expectLater(db.customStatement(sql), rejected);
      }
      expect(await originals(), before);
      expect(
        await db
            .customSelect('SELECT * FROM mutation_conflict_resolutions')
            .get(),
        hasLength(1),
      );
    },
  );
  test('stale attempt owner invalid choice missing revision and wrong target reject', () async {
    await expectLater(resolution(attempt: 2), rejected);
    await expectLater(resolution(user: target), rejected);
    await expectLater(resolution(choices: '{"name":"NEWEST_CLOCK"}'), rejected);
    await expectLater(resolution(proof: jsonEncode({'id': target})), rejected);
    await expectLater(
      resolution(proof: jsonEncode({'id': target, 'revision': 2.0})),
      rejected,
    );
    await expectLater(
      resolution(proof: jsonEncode({'id': owner, 'revision': 2})),
      rejected,
    );
    await expectLater(resolution(revision: 1), rejected);
    await expectLater(resolution(order: 2), rejected);
    expect(
      await db
          .customSelect('SELECT * FROM mutation_conflict_resolutions')
          .get(),
      isEmpty,
    );
  });
  test(
    'already attempted replacement and mismatched server baseline reject',
    () async {
      await db.customStatement(
        'UPDATE local_mutations SET attempt_count=1 WHERE op_id=?',
        [replacement],
      );
      await expectLater(resolution(), rejected);
      await expectLater(resolution(replace: original), rejected);
      expect(
        await db
            .customSelect('SELECT * FROM mutation_conflict_resolutions')
            .get(),
        isEmpty,
      );
    },
  );
  test(
    'non revision conflict cannot be resolved through this schema',
    () async {
      await db.customStatement(
        'UPDATE local_mutations SET server_response=? WHERE op_id=?',
        [
          jsonEncode({
            'status': 409,
            'code': 'TAG_ARCHIVED',
            'current': jsonDecode(snapshot(2)),
          }),
          original,
        ],
      );
      await expectLater(resolution(), rejected);
    },
  );
  test(
    'later conflict resolution must inherit the first request order',
    () async {
      await resolution();
      await db.customStatement(
        "UPDATE local_mutations SET queue_state='CONFLICT',attempt_count=1,server_response=? WHERE op_id=?",
        [
          jsonEncode({
            'status': 409,
            'code': 'REVISION_CONFLICT',
            'current': jsonDecode(snapshot(3)),
          }),
          replacement,
        ],
      );
      Future<void> next(String root, int order) => db.customStatement(
        'INSERT INTO mutation_conflict_resolutions VALUES(?,?,NULL,1,3,?,?,?, ?,0)',
        [replacement, owner, snapshot(3), '{}', root, order],
      );
      await expectLater(next(replacement, 2), rejected);
      await next(original, 1);
      expect(
        await db
            .customSelect('SELECT * FROM mutation_conflict_resolutions')
            .get(),
        hasLength(2),
      );
    },
  );
}
