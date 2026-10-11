import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/export/recordings_csv.dart';

const owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const token = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
String id(int n) => 'cccccccc-cccc-4ccc-8ccc-${n.toString().padLeft(12, '0')}';
final now = DateTime.utc(2026, 10, 11);
ExportData data({bool draft = false}) => ExportData.fromBaseline(
  ExportBaseline(
    id: token,
    owner: owner,
    includeTrash: false,
    manifest: null,
    createdAt: now,
    entries: const [],
    local: {
      'source_user_id': owner,
      'local_cutoff_at': now.toIso8601String(),
      'changes': <Object>[],
      'copies': [
        {
          'entity_type': 'SONG',
          'entity_id': id(1),
          'server_revision': 1,
          'tombstone': 0,
          'server_payload': null,
          'local_payload': jsonEncode({
            'id': id(1),
            'title': '곡, 이름',
            'artist': '가수',
          }),
        },
        {
          'entity_type': 'RECORDING',
          'entity_id': id(2),
          'server_revision': 1,
          'tombstone': 0,
          'server_payload': null,
          'local_payload': jsonEncode({
            'id': id(2),
            'song_id': id(1),
            'title_snapshot': null,
            'artist_snapshot': null,
            'version_code': 'LIVE',
            'metadata_state': draft ? 'DRAFT' : 'SAVED',
            'key_mode': 'FEMALE',
            'key_shift': 2,
            'recorded_at': '2026-10-11T00:00:00Z',
            'timezone_id': 'Asia/Seoul',
            'tier': 'A',
            'note': '메모 "인용"\n둘째 줄',
            'lifecycle_state': 'ACTIVE',
          }),
        },
      ],
      'recording_inputs': draft
          ? [
              {
                'recording_id': id(2),
                'phase': 'COMMITTED',
                'revision': 2,
                'recovery_payload': jsonEncode({
                  'input_form': {'title_snapshot': '=1+1', 'note': '@SUM(1,2)'},
                }),
              },
            ]
          : <Object>[],
    },
  ),
);
ExportManifest manifest({
  ExportMissingReason? reason,
  String exportId = token,
  int count = 2,
}) => ExportManifest(
  exportId: exportId,
  sourceUserId: owner,
  createdAt: now,
  localCutoffAt: now,
  online: false,
  includeTrash: false,
  snapshotCursor: null,
  serverBaselineComplete: false,
  serverConfirmedAt: null,
  serverCapturedAt: null,
  metadataCount: count,
  files: [
    ExportAudioEntry(
      recordingId: id(2),
      selected: true,
      included: reason == null,
      missingReason: reason,
      sha256: 'a' * 64,
      sizeBytes: 42,
      durationMs: 1234,
    ),
  ],
);

// Independent RFC 4180 readback, retaining a quoted multiline field as one cell.
List<List<String>> readCsv(String text) {
  final rows = <List<String>>[], row = <String>[];
  var cell = StringBuffer(), quoted = false;
  for (var i = text.startsWith('\ufeff') ? 1 : 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && c == ',') {
      row.add(cell.toString());
      cell = StringBuffer();
    } else if (!quoted && c == '\r' && text[i + 1] == '\n') {
      row.add(cell.toString());
      rows.add(List.of(row));
      row.clear();
      cell = StringBuffer();
      i++;
    } else {
      cell.write(c);
    }
  }
  expect(quoted, false);
  return rows;
}

void main() {
  test('formula prefixes, whitespace and controls are neutralized without deleting text', () {
    for (final text in [
      '=1+1',
      '+cmd',
      '-1+2',
      '@SUM(1,2)',
      ' \t=1',
      '\ttext',
      '\rtext',
      '\ntext',
      '\ufeff=1',
      '\u0001=1',
      '',
    ]) {
      final cell = backupCsvCell(text);
      if (text.isNotEmpty) {
        expect(cell, startsWith('"\''));
      } else {
        expect(cell, '""');
      }
    }
    expect(backupCsvCell('plain'), '"plain"');
    expect(backupCsvCell('a,"b"\nc'), '"a,""b""\nc"');
  });
  test('Korean CSV roundtrips commas quotes newlines and the required readable fields', () {
    final bytes = recordingsCsv(data(), manifest());
    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
    final text = utf8.decode(bytes);
    final rows = readCsv(text);
    expect(rows, hasLength(2));
    expect(rows.first, hasLength(13));
    expect(rows.last, hasLength(13));
    expect(rows.last, [
      id(2),
      '곡, 이름',
      '가수',
      'LIVE',
      '여 +2',
      '2026-10-11T00:00:00Z',
      'Asia/Seoul',
      'A',
      '메모 "인용"\n둘째 줄',
      '포함',
      '',
      '저장됨',
      'ACTIVE',
    ]);
  });
  test('missing file is explicit; unsaved completed-input values remain marked and escaped', () {
    final rows = readCsv(
      utf8.decode(
        recordingsCsv(
          data(draft: true),
          manifest(reason: ExportMissingReason.offlineServerOnly),
        ),
      ),
    );
    expect(rows.last[1], "'=1+1");
    expect(rows.last[8], "'@SUM(1,2)");
    expect(rows.last[9], '미포함');
    expect(rows.last[10], 'OFFLINE_SERVER_ONLY');
    expect(rows.last[11], '입력 대기 · 미저장 입력 포함');
  });
  test('different baseline, count mismatch and uncollected files never create final CSV', () {
    expect(
      () => recordingsCsv(data(), manifest(exportId: id(9))),
      throwsFormatException,
    );
    expect(
      () => recordingsCsv(data(), manifest(count: 3)),
      throwsFormatException,
    );
    expect(
      () => recordingsCsv(
        data(),
        manifest(reason: ExportMissingReason.notCollected),
      ),
      throwsFormatException,
    );
  });
}
