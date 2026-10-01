import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/metadata_conflict.dart';

import 'change_payload_validation_test.dart' show songChange, payloadId;

void main() {
  const time = '2026-10-01T00:00:00Z';
  Map<String, dynamic> tag(int revision) => {
    'id': payloadId,
    'revision': revision,
    'name': 'before',
    'archived_at': null,
    'updated_at': time,
  };
  QueuedMutation mutation({
    LocalEntity entity = LocalEntity.song,
    Map<String, dynamic>? base,
    Map<String, dynamic>? server,
    Map<String, dynamic>? patch,
    String state = 'CONFLICT',
    String code = 'REVISION_CONFLICT',
    int status = 409,
    LocalOperation operation = LocalOperation.patch,
    bool noBase = false,
  }) => QueuedMutation(
    opId: '11111111-1111-4111-8111-111111111111',
    localOrder: 1,
    entity: entity,
    entityId: payloadId,
    operation: operation,
    state: state,
    baseRevision: 1,
    attemptCount: 1,
    payload: jsonEncode(patch ?? {'base_revision': 1, 'note': 'local'}),
    basePayload: noBase ? null : jsonEncode(base ?? songChange(payloadId, 1)),
    serverResponse: jsonEncode({
      'code': code,
      'status': status,
      'current': server ?? songChange(payloadId, 2),
    }),
  );

  test('real song snapshot and patch produce only safe local fields', () {
    final m = mutation(server: songChange(payloadId, 2, title: 'remote'));
    final before = [m.payload, m.basePayload, m.serverResponse];
    final result = compareMetadataConflict(m)!;
    expect(result.safePatch, {'note': 'local'});
    expect(result.requiresChoice, isFalse);
    expect([m.payload, m.basePayload, m.serverResponse], before);
    expect(m.attemptCount, 1);
    expect(m.state, 'CONFLICT');
  });
  test(
    'conflicting memo remains a choice without choosing newer timestamp',
    () {
      final result = compareMetadataConflict(
        mutation(
          server: {
            ...songChange(payloadId, 2),
            'note': 'remote',
            'updated_at': '2099-01-01T00:00:00Z',
          },
        ),
      )!;
      expect(result.safePatch, isEmpty);
      expect(result.conflicts, [
        {'note'},
      ]);
    },
  );
  test('song key mode and shift are compared as one unit', () {
    final base = {
      ...songChange(payloadId, 1),
      'representative_key_mode': 'MALE',
      'representative_key_shift': 1,
    };
    final result = compareMetadataConflict(
      mutation(
        base: base,
        server: {...base, 'revision': 2, 'representative_key_mode': 'FEMALE'},
        patch: {'base_revision': 1, 'representative_key_shift': 2},
      ),
    )!;
    expect(result.conflicts, [
      {'representative_key_mode', 'representative_key_shift'},
    ]);
    expect(result.safePatch, isEmpty);
  });
  test('tag equal rename is a no-op while different rename conflicts', () {
    final same = mutation(
      entity: LocalEntity.tag,
      base: tag(1),
      server: {...tag(2), 'name': 'new'},
      patch: {'base_revision': 1, 'name': 'new'},
    );
    expect(compareMetadataConflict(same)!.safePatch, isEmpty);
    expect(compareMetadataConflict(same)!.requiresChoice, isFalse);
    expect(
      compareMetadataConflict(
        mutation(
          entity: LocalEntity.tag,
          base: tag(1),
          server: {...tag(2), 'name': 'other'},
          patch: {'base_revision': 1, 'name': 'new'},
        ),
      )!.conflicts,
      [
        {'name'},
      ],
    );
  });
  test('create unsupported entity missing evidence and other errors are not rebased', () {
    for (final m in [
      mutation(operation: LocalOperation.create),
      mutation(entity: LocalEntity.recording),
      mutation(noBase: true),
      mutation(code: 'CANONICAL_MAPPING_REQUIRED'),
      mutation(status: 400),
      mutation(state: 'RETRY'),
    ]) {
      expect(compareMetadataConflict(m), isNull);
    }
  });
  test('trash purge and archived tags do not produce resurrection patches', () {
    for (final state in ['TRASHED', 'PURGE_PENDING', 'PURGED']) {
      expect(
        compareMetadataConflict(
          mutation(
            server: {...songChange(payloadId, 2), 'lifecycle_state': state},
          ),
        ),
        isNull,
      );
    }
    expect(
      compareMetadataConflict(
        mutation(
          entity: LocalEntity.tag,
          base: tag(1),
          server: {...tag(2), 'archived_at': time},
          patch: {'base_revision': 1, 'name': 'new'},
        ),
      ),
      isNull,
    );
  });
  test('bad evidence revision mismatches and unknown fields fail closed', () {
    for (final m in [
      mutation(base: songChange(payloadId, 2)),
      mutation(server: songChange(payloadId, 1)),
      mutation(patch: {'base_revision': 2, 'note': 'new'}),
      mutation(patch: {'base_revision': 1, 'user_id': payloadId}),
      mutation(server: {...songChange(payloadId, 2), 'revision': 2.5}),
      mutation(server: {...songChange(payloadId, 2), 'id': 'other'}),
    ]) {
      expect(() => compareMetadataConflict(m), throwsFormatException);
    }
  });
  test('invalid intended local state cannot be labelled safe', () {
    for (final patch in <Map<String, dynamic>>[
      {'base_revision': 1, 'title': ''},
      {'base_revision': 1, 'tier': 'UNKNOWN'},
      {'base_revision': 1, 'representative_key_shift': 3},
      {'base_revision': 1, 'note': 123},
    ]) {
      expect(
        () => compareMetadataConflict(mutation(patch: patch)),
        throwsFormatException,
      );
    }
  });
  test('song source identity cannot change during a revision merge', () {
    expect(
      () => compareMetadataConflict(
        mutation(
          server: {
            ...songChange(payloadId, 2),
            'source_type': 'TJ',
            'tj_number': '123',
          },
        ),
      ),
      throwsFormatException,
    );
  });
}
