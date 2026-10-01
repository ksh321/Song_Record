import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/metadata_followup_plan.dart';
import 'package:song_record/core/sync/mutation_request.dart';

import 'recording_save_dispatch_test.dart' show draft, body;
import 'recording_tier_dispatch_test.dart' show rec, op;

const createOp = '44444444-4444-4444-8444-444444444444';
QueuedMutation followup({
  int attempts = 0,
  String state = 'PENDING',
  Map<String, Object?>? changes,
}) => QueuedMutation(
  opId: op,
  localOrder: 2,
  entity: LocalEntity.recording,
  entityId: rec,
  operation: LocalOperation.patch,
  state: state,
  baseRevision: 0,
  payload: jsonEncode(changes ?? {...body(), 'base_revision': 0}),
  attemptCount: attempts,
);
MutationRequest created({String state = 'ACKED', int attempts = 1}) {
  final payload = {
    'id': rec,
    'metadata_state': 'DRAFT',
    'song_id': null,
    'title_snapshot': 'recording',
    'artist_snapshot': 'artist',
    'version_code': 'NORMAL',
    'key_mode': 'ORIGINAL',
    'key_shift': 0,
    'note': 'preserved',
    'recorded_at': '2026-09-30T00:00:00Z',
    'timezone_id': 'UTC',
    'timezone_offset_minutes': 0,
  };
  final m = QueuedMutation(
    opId: createOp,
    localOrder: 1,
    entity: LocalEntity.recording,
    entityId: rec,
    operation: LocalOperation.create,
    state: state,
    baseRevision: 0,
    payload: jsonEncode(payload),
    attemptCount: attempts,
  );
  return MutationRequest(
    mutation: m,
    method: 'POST',
    path: '/v1/recordings',
    body: m.payload,
    attempt: attempts,
  );
}

void main() {
  MetadataFollowupPlan? derive({
    QueuedMutation? original,
    MutationRequest? prior,
    Map<String, dynamic>? current,
    bool tombstone = false,
    int order = 1,
  }) => MetadataFollowupPlan.derive(
    original: original ?? followup(),
    predecessor: prior ?? created(),
    receipt: MutationResponse(201, jsonEncode(draft())),
    predecessorLogicalOrder: order,
    current: current ?? Map<String, dynamic>.from(draft()),
    tombstone: tombstone,
  );

  test('offline save derives confirmed revision without changing original', () {
    final original = followup();
    final originalJson = original.payload;
    final plan = derive(original: original)!;
    expect(plan.originalOpId, op);
    expect(plan.predecessorOpId, createOp);
    expect(plan.revision, 1);
    expect(jsonDecode(plan.payloadJson), body());
    expect(jsonDecode(plan.baselineJson), draft());
    expect(original.payload, originalJson);
    expect(original.baseRevision, 0);
    expect(original.attemptCount, 0);
  });
  test(
    'newer remote state or divergent equal revision never silently rebases',
    () {
      expect(derive(current: {...draft(), 'revision': 2}), isNull);
      expect(derive(current: {...draft(), 'note': 'remote'}), isNull);
      expect(derive(tombstone: true), isNull);
    },
  );
  test(
    'only unsent pending work after an acknowledged predecessor qualifies',
    () {
      expect(derive(original: followup(attempts: 1)), isNull);
      expect(derive(original: followup(state: 'RETRY')), isNull);
      expect(derive(prior: created(state: 'SENDING')), isNull);
      expect(derive(prior: created(attempts: 0)), isNull);
      expect(derive(order: 2), isNull);
      expect(derive(order: 0), isNull);
    },
  );
  test('unsupported payload is preserved without emitting a replacement', () {
    final original = followup(changes: {'base_revision': 0, 'unknown': true});
    expect(derive(original: original), isNull);
    expect(jsonDecode(original.payload)['unknown'], isTrue);
  });
}
