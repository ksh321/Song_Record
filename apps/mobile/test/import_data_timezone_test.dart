import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/import/import_validation.dart';

void main() {
  const owner = '11111111-1111-4111-8111-111111111111',
      id = '00000000-0000-4000-8000-000000001002';
  ImportData decode(Object timezone, {String? song}) {
    final now = DateTime.utc(2026, 10, 12);
    final baseline = ExportBaseline(
      id: id,
      owner: owner,
      includeTrash: false,
      manifest: null,
      createdAt: now,
      entries: const [],
      local: {
        'source_user_id': owner,
        'local_cutoff_at': now.toIso8601String(),
        'baseline': [
          {'baseline_complete': 0, 'last_change_seq': null, 'updated_at': null},
        ],
        'copies': [
          {
            'entity_type': 'RECORDING',
            'entity_id': id,
            'server_revision': 0,
            'tombstone': 0,
            'server_payload': null,
            'local_payload': jsonEncode({
              'id': id,
              'song_id': song,
              'timezone_id': timezone,
              'timezone_offset_minutes': 540,
              'recorded_at': now.toIso8601String(),
              'metadata_state': 'SAVED',
            }),
          },
        ],
        'changes': <Object?>[],
        'recording_inputs': <Object?>[],
      },
    );
    final data = ExportData.fromBaseline(baseline),
        manifest = ExportManifest.fromBaseline(
          baseline,
          metadataCount: 1,
          files: const [],
        );
    return ImportData.decode(data.encode(), manifest);
  }

  test('exported timezone is a timezone name, never a resource UUID', () {
    for (final zone in ['Asia/Seoul', 'UTC', 'America/New_York']) {
      expect(
        ((decode(zone).toJson()['records'] as List).single['payload']
            as Map)['timezone_id'],
        zone,
      );
    }
  });
  test('present timezone must be a bounded nonempty string', () {
    for (final zone in ['', 'a' * 65, 42, true]) {
      expect(() => decode(zone), throwsFormatException);
    }
  });
  test('actual UUID references remain strictly validated', () {
    expect(
      () => decode('Asia/Seoul', song: 'not-a-uuid'),
      throwsFormatException,
    );
  });
}
