import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';

import 'change_payload_validation_test.dart'
    show songChange, payloadId, recordingWire;

void main() {
  QueuedMutation mutation({
    Map<String, dynamic>? base,
    Map<String, dynamic>? server,
    Map<String, dynamic>? patch,
    LocalEntity entity = LocalEntity.song,
  }) => QueuedMutation(
    opId: '11111111-1111-4111-8111-111111111111',
    localOrder: 1,
    entity: entity,
    entityId: payloadId,
    operation: LocalOperation.patch,
    state: 'CONFLICT',
    baseRevision: 1,
    payload: jsonEncode(patch ?? {'base_revision': 1, 'note': 'local'}),
    basePayload: jsonEncode(base ?? songChange(payloadId, 1)),
    serverResponse: jsonEncode({
      'status': 409,
      'code': 'REVISION_CONFLICT',
      'current': server ?? {...songChange(payloadId, 2), 'note': 'remote'},
    }),
    attemptCount: 1,
  );

  test(
    'different fields create a new-base proposal without editing source',
    () {
      final source = mutation(
        server: songChange(payloadId, 2, title: 'remote'),
      );
      final before = [
        source.payload,
        source.basePayload,
        source.serverResponse,
      ];
      final plan = prepareConflictResolution(source);
      expect(jsonDecode(plan.patchJson!), {
        'base_revision': 2,
        'note': 'local',
      });
      expect(jsonDecode(plan.serverJson)['title'], 'remote');
      expect(plan.choicesJson, '{}');
      expect([
        source.payload,
        source.basePayload,
        source.serverResponse,
      ], before);
      expect(source.attemptCount, 1);
      expect(source.state, 'CONFLICT');
    },
  );
  test('same field requires exact explicit choices', () {
    final source = mutation();
    expect(() => prepareConflictResolution(source), throwsStateError);
    expect(
      () => prepareConflictResolution(
        source,
        choices: {'title': ConflictChoice.local},
      ),
      throwsStateError,
    );
    expect(
      () => prepareConflictResolution(
        source,
        choices: {'note': ConflictChoice.local, 'title': ConflictChoice.server},
      ),
      throwsStateError,
    );
    expect(
      jsonDecode(
        prepareConflictResolution(
          source,
          choices: {'note': ConflictChoice.local},
        ).patchJson!,
      ),
      {'base_revision': 2, 'note': 'local'},
    );
  });
  test('server choice is retained even when no request is needed', () {
    final plan = prepareConflictResolution(
      mutation(),
      choices: {'note': ConflictChoice.server},
    );
    expect(plan.needsRequest, isFalse);
    expect(plan.patchJson, isNull);
    expect(jsonDecode(plan.choicesJson), {'note': 'SERVER'});
  });
  test('server choice preserves unrelated safe edits', () {
    final plan = prepareConflictResolution(
      mutation(
        patch: {'base_revision': 1, 'note': 'local', 'title': 'local title'},
      ),
      choices: {'note': ConflictChoice.server},
    );
    expect(jsonDecode(plan.patchJson!), {
      'base_revision': 2,
      'title': 'local title',
    });
  });
  test('key mode and shift cannot choose inconsistent sides', () {
    final base = {
      ...songChange(payloadId, 1),
      'representative_key_mode': 'MALE',
      'representative_key_shift': 1,
    };
    final source = mutation(
      base: base,
      server: {...base, 'revision': 2, 'representative_key_mode': 'FEMALE'},
      patch: {'base_revision': 1, 'representative_key_shift': 2},
    );
    expect(
      () => prepareConflictResolution(
        source,
        choices: {
          'representative_key_mode': ConflictChoice.server,
          'representative_key_shift': ConflictChoice.local,
        },
      ),
      throwsStateError,
    );
    final plan = prepareConflictResolution(
      source,
      choices: {
        'representative_key_mode': ConflictChoice.local,
        'representative_key_shift': ConflictChoice.local,
      },
    );
    expect(jsonDecode(plan.patchJson!), {
      'base_revision': 2,
      'representative_key_mode': 'MALE',
      'representative_key_shift': 2,
    });
  });
  test('equal values produce no request and reject unrelated choices', () {
    final source = mutation(
      server: {...songChange(payloadId, 2), 'note': 'local'},
    );
    expect(prepareConflictResolution(source).needsRequest, isFalse);
    expect(
      () => prepareConflictResolution(
        source,
        choices: {'note': ConflictChoice.local},
      ),
      throwsStateError,
    );
  });
  test('proposal is detached and redacts personal metadata', () {
    final choices = {'note': ConflictChoice.local};
    final plan = prepareConflictResolution(mutation(), choices: choices);
    choices['note'] = ConflictChoice.server;
    expect(jsonDecode(plan.choicesJson), {'note': 'LOCAL'});
    expect(plan.toString(), 'ConflictResolutionPlan[REDACTED]');
  });
  test(
    'fractional base revision and deleted server cannot produce requests',
    () {
      expect(
        () => prepareConflictResolution(
          mutation(patch: {'base_revision': 1.0, 'note': 'local'}),
          choices: {'note': ConflictChoice.local},
        ),
        throwsFormatException,
      );
      expect(
        () => prepareConflictResolution(
          mutation(
            server: {...songChange(payloadId, 2), 'lifecycle_state': 'TRASHED'},
          ),
        ),
        throwsStateError,
      );
    },
  );
  test('recording time group uses complete original local values', () {
    final base = {
      ...recordingWire('RecordingEdited'),
      'id': payloadId,
      'revision': 1,
    };
    final server = {
      ...base,
      'revision': 2,
      'recorded_at': '2026-10-01T10:00:00Z',
    };
    final source = mutation(
      entity: LocalEntity.recording,
      base: base,
      server: server,
      patch: {'base_revision': 1, 'recorded_at': '2026-10-01T11:00:00Z'},
    );
    final plan = prepareConflictResolution(
      source,
      choices: {
        'recorded_at': ConflictChoice.local,
        'timezone_id': ConflictChoice.local,
        'timezone_offset_minutes': ConflictChoice.local,
      },
    );
    expect(jsonDecode(plan.patchJson!), {
      'base_revision': 2,
      'recorded_at': '2026-10-01T11:00:00Z',
      'timezone_id': base['timezone_id'],
      'timezone_offset_minutes': base['timezone_offset_minutes'],
    });
  });
}
