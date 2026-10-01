import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_payload_validation.dart';

const payloadId = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> songChange(
  String id,
  int revision, {
  String title = 'server',
}) => {
  'id': id,
  'revision': revision,
  'updated_at': '2026-10-01T00:00:00Z',
  'source_type': 'MANUAL',
  'tj_number': null,
  'title': title,
  'artist': 'artist',
  'version_code': 'NORMAL',
  'tier': null,
  'note': '',
  'lifecycle_state': 'ACTIVE',
  'representative_recording_id': null,
  'representative_key_mode': null,
  'representative_key_shift': null,
};
Map<String, dynamic> recordingWire(String schema) {
  final cases = jsonDecode(
    File('../../fixtures/contracts/api-schema-cases.json').readAsStringSync(),
  ) as List;
  return Map<String, dynamic>.from(
    cases.firstWhere(
          (c) => c['schema'] == schema && c['valid'] == true,
        )['value']
        as Map,
  );
}

void main() {
  test(
    'playlist header validates its own fields without inventing item revision',
    () {
      final value = <String, dynamic>{
        'id': payloadId,
        'revision': 1,
        'name': '목록',
        'deleted_at': null,
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      };
      validateChangePayload(LocalEntity.playlist, value);
      expect(
        () =>
            validateChangePayload(LocalEntity.playlist, {...value, 'name': ''}),
        throwsFormatException,
      );
      expect(
        () => validateChangePayload(LocalEntity.playlist, {
          ...value,
          'deleted_at': '2026-02-30T00:00:00Z',
        }),
        throwsFormatException,
      );
      expect(
        () => validateChangePayload(LocalEntity.playlist, {
          ...value,
          'items': <Object?>[],
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'retained Condition accepts fixed codes and its own legacy UUID only',
    () {
      final value = <String, dynamic>{
        'id': payloadId,
        'revision': 2,
        'name': '과거 이름',
        'code': payloadId,
        'archived_at': '2026-10-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      };
      final before = jsonEncode(value);
      validateChangePayload(LocalEntity.recordingCondition, value);
      expect(jsonEncode(value), before);
      for (final code in ['VERY_GOOD', 'GOOD', 'NORMAL', 'BAD']) {
        validateChangePayload(LocalEntity.recordingCondition, {
          ...value,
          'code': code,
        });
      }
      for (final code in [
        'UNKNOWN',
        '11111111-1111-4111-8111-111111111111',
        null,
      ]) {
        expect(
          () => validateChangePayload(LocalEntity.recordingCondition, {
            ...value,
            'code': code,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => validateChangePayload(LocalEntity.recordingCondition, {
          ...value,
          'name': '',
        }),
        throwsFormatException,
      );
    },
  );
  test('actual recording draft, saved and edited shared contract variants validate', () {
    for (final schema in [
      'RecordingDraft',
      'RecordingSaved',
      'RecordingEdited',
    ]) {
      expect(
        () =>
            validateChangePayload(LocalEntity.recording, recordingWire(schema)),
        returnsNormally,
      );
    }
  });
  test(
    'missing core fields and unexpected fields cannot replace song state',
    () {
      final valid = songChange(payloadId, 2);
      expect(
        () => validateChangePayload(LocalEntity.song, valid),
        returnsNormally,
      );
      for (final field in valid.keys) {
        final broken = Map<String, dynamic>.from(valid)..remove(field);
        expect(
          () => validateChangePayload(LocalEntity.song, broken),
          throwsFormatException,
          reason: field,
        );
      }
      expect(
        () => validateChangePayload(LocalEntity.song, {
          ...valid,
          'secret_field': 'x',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'source number, enum, key pair and real UTC calendar bounds are checked',
    () {
      final values = <String, Object?>{
        'source_type': 'UNKNOWN',
        'tier': 'Z',
        'version_code': 'K',
        'representative_key_shift': 1,
        'updated_at': '2026-02-30T00:00:00Z',
        'revision': 2.0,
      };
      for (final entry in values.entries) {
        expect(
          () => validateChangePayload(LocalEntity.song, {
            ...songChange(payloadId, 2),
            entry.key: entry.value,
          }),
          throwsFormatException,
        );
      }
      final tj = {
        ...songChange(payloadId, 2),
        'source_type': 'TJ',
        'tj_number': '000123',
      };
      validateChangePayload(LocalEntity.song, tj);
      expect(tj['tj_number'], '000123');
      expect(
        () =>
            validateChangePayload(LocalEntity.song, {...tj, 'tj_number': 123}),
        throwsFormatException,
      );
    },
  );
  test('tags match by UUID set and explicit empty relations are valid', () {
    final value = recordingWire('RecordingEdited');
    value['tag_ids'] = [payloadId];
    value['tags'] = [
      {'id': payloadId, 'name_snapshot': 'old name'},
    ];
    validateChangePayload(LocalEntity.recording, value);
    value['tag_ids'] = [payloadId, payloadId];
    expect(
      () => validateChangePayload(LocalEntity.recording, value),
      throwsFormatException,
    );
    value['tag_ids'] = <String>[];
    expect(
      () => validateChangePayload(LocalEntity.recording, value),
      throwsFormatException,
    );
  });
  test('file specification limits reject coercion, corruption and unknown properties', () {
    for (final change in <String, Object?>{
      'size_bytes': 6291457,
      'channels': 1.0,
      'sha256': 'wrong',
      'codec': 'MP3',
      'unexpected': true,
    }.entries) {
      final value = recordingWire('RecordingSaved');
      (value['file'] as Map)[change.key] = change.value;
      expect(
        () => validateChangePayload(LocalEntity.recording, value),
        throwsFormatException,
      );
    }
  });
  test('tag archive and historical condition UUID are preserved without normalization', () {
    final tag = <String, dynamic>{
      'id': payloadId,
      'revision': 2,
      'updated_at': '2026-10-01T00:00:00Z',
      'name': 'old name',
      'archived_at': '2026-09-30T00:00:00Z',
    };
    validateChangePayload(LocalEntity.tag, tag);
    final value = recordingWire('RecordingEdited');
    value['condition_code'] = payloadId;
    value['condition_name_snapshot'] = 'old condition';
    validateChangePayload(LocalEntity.recording, value);
    expect(value['condition_code'], payloadId);
    expect(
      () => validateChangePayload(LocalEntity.playlist, tag),
      throwsFormatException,
    );
  });
}
