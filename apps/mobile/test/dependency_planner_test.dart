import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/dependency_planner.dart';
import 'package:song_record/core/sync/mutation_request.dart';

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
QueuedMutation mutation(
  int op,
  LocalEntity entity,
  int target, {
  int? order,
  String state = 'PENDING',
  LocalOperation operation = LocalOperation.create,
  int base = 0,
  Map<String, Object?> body = const {},
}) => QueuedMutation(
  opId: id(op),
  localOrder: order ?? op,
  entity: entity,
  entityId: id(target),
  operation: operation,
  state: state,
  baseRevision: base,
  payload: jsonEncode(body),
  attemptCount: 0,
);
DispatchPlan plan(
  List<QueuedMutation> pending, {
  Map<LocalTarget, ServerBaseline> baselines = const {},
}) => const DependencyPlanner().plan(
  DispatchSnapshot(pending: pending, baselines: baselines),
);
const known = ServerBaseline(revision: 1, tombstone: false);

void main() {
  test('missing song blocks only its recordings, not unrelated work', () {
    final result = plan([
      mutation(1, LocalEntity.song, 10, state: 'FAILED'),
      mutation(2, LocalEntity.recording, 20, body: {'song_id': id(10)}),
      mutation(3, LocalEntity.recording, 21),
      mutation(4, LocalEntity.song, 11),
    ]);
    expect(result.ready.map((m) => m.opId), [id(4), id(3)]);
    expect(result.waiting[id(1)]!.reason, DispatchWaitReason.queueState);
    expect(result.waiting[id(2)]!.reason, DispatchWaitReason.missingDependency);
    expect(
      result.waiting[id(2)]!.dependency,
      LocalTarget(LocalEntity.song, id(10)),
    );
  });

  test('ready parent is not mistaken for acknowledged parent', () {
    final queue = [
      mutation(1, LocalEntity.song, 10),
      mutation(2, LocalEntity.recording, 20, body: {'song_id': id(10)}),
    ];
    expect(plan(queue).ready.map((m) => m.opId), [id(1)]);
    final afterAck = plan(
      [queue.last],
      baselines: {LocalTarget(LocalEntity.song, id(10)): known},
    );
    expect(afterAck.ready.map((m) => m.opId), [id(2)]);
  });

  test('database order wins over lexicographic operation UUID', () {
    final result = plan([
      mutation(10, LocalEntity.song, 1, order: 2),
      mutation(90, LocalEntity.song, 1, order: 1),
    ]);
    expect(result.ready.single.opId, id(90));
    expect(result.waiting[id(10)]!.reason, DispatchWaitReason.earlierMutation);
  });

  test('conflict, in-flight and retry heads hold later same-target work', () {
    for (final state in ['CONFLICT', 'SENDING', 'RETRY', 'FAILED']) {
      final result = plan([
        mutation(1, LocalEntity.song, 10, state: state),
        mutation(2, LocalEntity.song, 10),
        mutation(3, LocalEntity.song, 11),
      ]);
      expect(result.ready.single.opId, id(3));
      expect(result.waiting[id(2)]!.reason, DispatchWaitReason.earlierMutation);
    }
  });

  test('patch waits for unresolved or stale baseline without rewriting it', () {
    final unresolved = mutation(
      1,
      LocalEntity.song,
      10,
      operation: LocalOperation.patch,
      body: {'base_revision': 0, 'title': 'keep'},
    );
    final before = unresolved.payload;
    expect(
      plan([unresolved]).waiting[id(1)]!.reason,
      DispatchWaitReason.unresolvedBaseline,
    );
    expect(unresolved.payload, before);
    final stale = mutation(
      2,
      LocalEntity.song,
      10,
      operation: LocalOperation.patch,
      base: 2,
      body: {'base_revision': 2},
    );
    expect(
      plan(
        [stale],
        baselines: {LocalTarget(LocalEntity.song, id(10)): known},
      ).waiting[id(2)]!.reason,
      DispatchWaitReason.staleBaseline,
    );
    final valid = mutation(
      3,
      LocalEntity.song,
      10,
      operation: LocalOperation.patch,
      base: 1,
      body: {'base_revision': 1},
    );
    expect(
      plan(
        [valid],
        baselines: {LocalTarget(LocalEntity.song, id(10)): known},
      ).ready.single.opId,
      id(3),
    );
  });

  test('tags must exist and explicit null song clears the dependency', () {
    final m = mutation(
      1,
      LocalEntity.recording,
      20,
      body: {
        'song_id': null,
        'tag_ids': [id(30)],
        'condition_code': 'GOOD',
      },
    );
    expect(plan([m]).ready, isEmpty);
    expect(
      plan(
        [m],
        baselines: {LocalTarget(LocalEntity.tag, id(30)): known},
      ).ready.single.opId,
      id(1),
    );
  });

  test('deleted dependencies and deleted targets never become ready', () {
    const deleted = ServerBaseline(revision: 3, tombstone: true);
    final result = plan(
      [
        mutation(1, LocalEntity.song, 10),
        mutation(2, LocalEntity.recording, 20, body: {'song_id': id(10)}),
      ],
      baselines: {LocalTarget(LocalEntity.song, id(10)): deleted},
    );
    expect(result.ready, isEmpty);
    expect(
      result.waiting.values.every(
        (w) => w.reason == DispatchWaitReason.deletedTarget,
      ),
      isTrue,
    );
  });

  test('new offline draft may reach server for deleted song without rewriting input', () {
    const deleted = ServerBaseline(revision: 3, tombstone: true);
    final draft = mutation(
      1,
      LocalEntity.recording,
      20,
      body: {
        'id': id(20),
        'metadata_state': 'DRAFT',
        'song_id': id(10),
        'note': 'keep',
      },
    );
    final before = draft.payload;
    final result = plan(
      [draft],
      baselines: {LocalTarget(LocalEntity.song, id(10)): deleted},
    );
    expect(result.ready.single.opId, draft.opId);
    expect(draft.payload, before);
    final edit = mutation(
      2,
      LocalEntity.recording,
      21,
      operation: LocalOperation.patch,
      base: 1,
      body: {'base_revision': 1, 'song_id': id(10)},
    );
    expect(
      plan(
        [edit],
        baselines: {
          LocalTarget(LocalEntity.song, id(10)): deleted,
          LocalTarget(LocalEntity.recording, id(21)): known,
        },
      ).waiting[edit.opId]!.reason,
      DispatchWaitReason.deletedTarget,
    );
    expect(
      plan([draft]).waiting[draft.opId]!.reason,
      DispatchWaitReason.missingDependency,
    );
    final deletedRecording = plan(
      [draft],
      baselines: {
        LocalTarget(LocalEntity.song, id(10)): deleted,
        LocalTarget(LocalEntity.recording, id(20)): deleted,
      },
    );
    expect(
      deletedRecording.waiting[draft.opId]!.reason,
      DispatchWaitReason.deletedTarget,
    );
  });
  test('classification, song, recording and relation phases are ordered', () {
    final result = plan(
      [
        mutation(
          1,
          LocalEntity.playlistItem,
          40,
          body: {'playlist_id': id(30), 'song_id': id(10)},
        ),
        mutation(2, LocalEntity.recording, 20),
        mutation(3, LocalEntity.tag, 50),
        mutation(4, LocalEntity.song, 11),
      ],
      baselines: {
        LocalTarget(LocalEntity.playlist, id(30)): known,
        LocalTarget(LocalEntity.song, id(10)): known,
      },
    );
    expect(result.ready.map((m) => m.opId), [id(3), id(4), id(2), id(1)]);
  });

  test('unsupported condition mapping and file work stay visible', () {
    final result = plan([
      mutation(1, LocalEntity.recordingCondition, 30),
      mutation(2, LocalEntity.recording, 20, body: {'condition_code': id(30)}),
      mutation(3, LocalEntity.recordingAsset, 20),
    ]);
    expect(result.ready, isEmpty);
    expect(result.waiting, hasLength(3));
    expect(
      result.waiting.values.every(
        (w) => w.reason == DispatchWaitReason.unsupported,
      ),
      isTrue,
    );
  });

  for (final relation in [
    (
      entity: LocalEntity.playlistItem,
      body: {'playlist_id': id(30), 'song_id': id(10)},
      parents: [
        LocalTarget(LocalEntity.playlist, id(30)),
        LocalTarget(LocalEntity.song, id(10)),
      ],
    ),
    (
      entity: LocalEntity.recordingTag,
      body: {'recording_id': id(20), 'tag_id': id(50)},
      parents: [
        LocalTarget(LocalEntity.recording, id(20)),
        LocalTarget(LocalEntity.tag, id(50)),
      ],
    ),
  ]) {
    test('${relation.entity.code} requires both acknowledged parents', () {
      final child = mutation(1, relation.entity, 60, body: relation.body);
      final parents = [
        for (var i = 0; i < relation.parents.length; i++)
          QueuedMutation(
            opId: id(100 + i),
            localOrder: 100 + i,
            entity: relation.parents[i].entity,
            entityId: relation.parents[i].id,
            operation: LocalOperation.create,
            state: 'PENDING',
            baseRevision: 0,
            payload: '{}',
            attemptCount: 0,
          ),
      ];
      // Even ready parents cannot release a child before their ACKs commit.
      final before = plan([child, ...parents]);
      expect(before.ready.map((m) => m.opId), isNot(contains(child.opId)));
      expect(
        before.waiting[child.opId]!.reason,
        DispatchWaitReason.missingDependency,
      );
      for (final missing in relation.parents) {
        final remaining = {
          for (final parent in relation.parents)
            if (parent != missing) parent: known,
        };
        final waiting = plan([child], baselines: remaining);
        expect(waiting.ready, isEmpty);
        expect(waiting.waiting[child.opId]!.dependency, missing);
        expect(
          waiting.waiting[child.opId]!.reason,
          DispatchWaitReason.missingDependency,
        );

        final deleted = plan(
          [child],
          baselines: {
            ...remaining,
            missing: const ServerBaseline(revision: 2, tombstone: true),
          },
        );
        expect(deleted.ready, isEmpty);
        expect(deleted.waiting[child.opId]!.dependency, missing);
        expect(
          deleted.waiting[child.opId]!.reason,
          DispatchWaitReason.deletedTarget,
        );
      }
      final after = plan(
        [child],
        baselines: {for (final parent in relation.parents) parent: known},
      );
      expect(after.ready.single.opId, child.opId);
      expect(after.waiting, isEmpty);
      // Dependency-ready does not invent a P19/standalone relation HTTP route.
      expect(MutationRequest.prepare(after.ready.single), isNull);
      expect(child.payload, jsonEncode(relation.body));
      expect(child.attemptCount, 0);
    });

    test('${relation.entity.code} rejects absent or malformed references', () {
      for (final field in relation.body.keys) {
        for (final invalid in [null, 7, 'not-a-uuid']) {
          final child = mutation(
            1,
            relation.entity,
            60,
            body: {...relation.body, field: invalid},
          );
          final result = plan(
            [child],
            baselines: {for (final parent in relation.parents) parent: known},
          );
          expect(result.ready, isEmpty);
          expect(
            result.waiting[child.opId]!.reason,
            DispatchWaitReason.invalidPayload,
          );
        }
        final omitted = Map<String, Object?>.from(relation.body)..remove(field);
        expect(
          plan([mutation(1, relation.entity, 60, body: omitted)])
              .waiting[id(1)]!
              .reason,
          DispatchWaitReason.invalidPayload,
        );
      }
    });
  }

  test('all metadata phases precede held file work without consuming it', () {
    final queue = [
      mutation(1, LocalEntity.recordingAsset, 20),
      mutation(2, LocalEntity.recordingFileSpec, 20),
      mutation(
        3,
        LocalEntity.recordingTag,
        60,
        body: {'recording_id': id(20), 'tag_id': id(50)},
      ),
      mutation(
        4,
        LocalEntity.playlistItem,
        40,
        body: {'playlist_id': id(30), 'song_id': id(10)},
      ),
      mutation(5, LocalEntity.playlist, 31),
      mutation(6, LocalEntity.recording, 21),
      mutation(7, LocalEntity.song, 11),
      mutation(8, LocalEntity.tag, 51),
    ];
    final result = plan(
      queue,
      baselines: {
        LocalTarget(LocalEntity.recording, id(20)): known,
        LocalTarget(LocalEntity.tag, id(50)): known,
        LocalTarget(LocalEntity.playlist, id(30)): known,
        LocalTarget(LocalEntity.song, id(10)): known,
      },
    );
    expect(result.ready.map((m) => m.opId), [
      id(7),
      id(8),
      id(6),
      id(3),
      id(4),
      id(5),
    ]);
    expect(result.waiting.keys, unorderedEquals([id(1), id(2)]));
    for (final file in queue.take(2)) {
      expect(result.waiting[file.opId]!.reason, DispatchWaitReason.unsupported);
      expect(MutationRequest.prepare(file), isNull);
      expect(file.state, 'PENDING');
      expect(file.attemptCount, 0);
      expect(file.payload, '{}');
    }
  });

  test(
    'logical predecessor holds younger canonical aliases until released',
    () {
      final original = mutation(1, LocalEntity.song, 10);
      final younger = mutation(2, LocalEntity.song, 11);
      final replacement = mutation(3, LocalEntity.song, 10, order: 99);
      final unrelated = mutation(4, LocalEntity.tag, 50);
      final group = LocalTarget(LocalEntity.song, id(11));
      DispatchPlan mapped({required bool held}) =>
          const DependencyPlanner().plan(
            DispatchSnapshot(
              pending: [younger, replacement, original, unrelated],
              baselines: const {},
              mapping: MappingEligibility(
                blocked: {if (held) replacement.opId},
                superseded: {original.opId},
                logicalOrders: {replacement.opId: 1},
                groups: {LocalTarget(LocalEntity.song, id(10)): group},
              ),
            ),
          );
      final held = mapped(held: true);
      expect(held.ready.map((m) => m.opId), [unrelated.opId]);
      expect(
        held.waiting[original.opId]!.reason,
        DispatchWaitReason.superseded,
      );
      expect(
        held.waiting[replacement.opId]!.reason,
        DispatchWaitReason.mappingBlocked,
      );
      expect(
        held.waiting[younger.opId]!.reason,
        DispatchWaitReason.earlierMutation,
      );
      final released = mapped(held: false);
      expect(released.ready.map((m) => m.opId), [
        replacement.opId,
        unrelated.opId,
      ]);
      expect(
        released.waiting[younger.opId]!.reason,
        DispatchWaitReason.earlierMutation,
      );
      expect(replacement.localOrder, 99);
      expect(original.state, 'PENDING');
    },
  );

  test('malformed references are held and dependency cycles do not spin', () {
    final malformed = plan([
      mutation(1, LocalEntity.recording, 20, body: {'tag_ids': 'bad'}),
      mutation(2, LocalEntity.recording, 21, body: {'song_id': 'bad'}),
    ]);
    expect(
      malformed.waiting.values.every(
        (w) => w.reason == DispatchWaitReason.invalidPayload,
      ),
      isTrue,
    );
    final cycle = plan([
      mutation(
        3,
        LocalEntity.song,
        10,
        body: {'representative_recording_id': id(20)},
      ),
      mutation(4, LocalEntity.recording, 20, body: {'song_id': id(10)}),
    ]);
    expect(cycle.ready, isEmpty);
    expect(cycle.waiting, hasLength(2));
  });

  test(
    'plan collections are immutable and acknowledged entries are ignored',
    () {
      final result = plan([
        mutation(1, LocalEntity.song, 10, state: 'ACKED'),
        mutation(2, LocalEntity.song, 10),
      ]);
      expect(result.ready.single.opId, id(2));
      expect(() => result.ready.clear(), throwsUnsupportedError);
      expect(() => result.waiting.clear(), throwsUnsupportedError);
    },
  );
}
