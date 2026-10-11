import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/export/backup_json.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';

const exportId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const owner = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
String id(int n) => 'cccccccc-cccc-4ccc-8ccc-${n.toString().padLeft(12, '0')}';
ExportAudioEntry included(int n) => ExportAudioEntry(
  recordingId: id(n),
  selected: true,
  included: true,
  missingReason: null,
  sha256: 'a' * 64,
  sizeBytes: 100,
  durationMs: 1000,
);
ExportManifest manifest({bool online = false, List<ExportAudioEntry>? files}) =>
    ExportManifest(
      exportId: exportId,
      sourceUserId: owner,
      createdAt: DateTime.utc(2026, 10, 11),
      localCutoffAt: DateTime.utc(2026, 10, 11),
      online: online,
      includeTrash: false,
      snapshotCursor: online ? 42 : null,
      serverBaselineComplete: online,
      serverConfirmedAt: online ? DateTime.utc(2026, 10, 10) : null,
      serverCapturedAt: online ? DateTime.utc(2026, 10, 10) : null,
      metadataCount: 3,
      files: files ?? [included(1)],
    );

void main() {
  test('offline confirmed provenance keeps a real zero cursor and unknown time stays null', () {
    ExportManifest convert(int complete, int? cursor, int? updated) =>
        ExportManifest.fromBaseline(
          ExportBaseline(
            id: exportId,
            owner: owner,
            includeTrash: false,
            manifest: null,
            createdAt: DateTime.utc(2026, 10, 11),
            entries: const [],
            local: {
              'source_user_id': owner,
              'local_cutoff_at': '2026-10-11T00:00:00Z',
              'baseline': [
                {
                  'baseline_complete': complete,
                  'last_change_seq': cursor,
                  'updated_at': updated,
                },
              ],
            },
          ),
          metadataCount: 0,
          files: const [],
        );
    final incomplete = convert(0, 42, 1234);
    expect(incomplete.snapshotCursor, isNull);
    expect(incomplete.serverConfirmedAt, isNull);
    final confirmed = convert(1, 0, null);
    expect(confirmed.snapshotCursor, 0);
    expect(confirmed.serverBaselineComplete, isTrue);
    expect(confirmed.serverConfirmedAt, isNull);
    expect(confirmed.canClaimCompleteOnline, isFalse);
  });
  test('backup JSON rejects decoded duplicate keys, malformed and excessive nesting without source logs', () {
    for (final text in [
      '{"a":1,"\\u0061":2}',
      '[',
      '{"a":}',
      '{} true',
      '${'[' * 66}0${']' * 66}',
    ]) {
      expect(
        () => decodeBackupJson(text),
        throwsA(
          isA<FormatException>().having(
            (error) => error.source,
            'no private source',
            isNull,
          ),
        ),
      );
    }
    expect(decodeBackupJson(r'{"text":"a\"b\\c"}'), {'text': 'a"b\\c'});
  });
  test(
    'schema 1 roundtrip keeps null offline cursor and never claims full online',
    () {
      final source = manifest();
      final restored = ExportManifest.decode(source.encode());
      expect(restored.snapshotCursor, isNull);
      expect(restored.serverBaselineComplete, isFalse);
      expect(restored.canClaimCompleteOnline, isFalse);
      expect(restored.toJson(), source.toJson());
      expect(restored.files.single.relativePath, 'audio/${id(1)}.m4a');
      expect(restored.includedAudioBytes, 100);
    },
  );
  test('selected missing audio differs from deliberately excluded trash', () {
    final value = manifest(
      online: true,
      files: [
        included(1),
        ExportAudioEntry(
          recordingId: id(2),
          selected: true,
          included: false,
          missingReason: ExportMissingReason.fileNotOnDevice,
        ),
        ExportAudioEntry(
          recordingId: id(3),
          selected: false,
          included: false,
          missingReason: ExportMissingReason.trashNotSelected,
        ),
      ],
    );
    expect(value.includedAudioCount, 1);
    expect(value.missingAudioCount, 1);
    expect(value.excludedAudioCount, 1);
    expect(value.canClaimCompleteOnline, isFalse);
    final excludedOnly = manifest(online: true, files: [value.files.last]);
    expect(excludedOnly.missingAudioCount, 0);
    expect(excludedOnly.canClaimCompleteOnline, isTrue);
    expect(ExportManifest.decode(value.encode()).toJson(), value.toJson());
  });
  test('missing expected hash is not an included file proof', () {
    final entry = ExportAudioEntry(
      recordingId: id(1),
      selected: true,
      included: false,
      missingReason: ExportMissingReason.offlineServerOnly,
      sha256: 'a' * 64,
      sizeBytes: 100,
      durationMs: 1000,
    );
    expect(entry.relativePath, isNull);
    expect(manifest(files: [entry]).includedAudioBytes, 0);
    expect(
      () => ExportAudioEntry(
        recordingId: id(1),
        selected: true,
        included: true,
        missingReason: null,
      ),
      throwsFormatException,
    );
    expect(
      () => ExportAudioEntry(
        recordingId: id(1),
        selected: true,
        included: false,
        missingReason: ExportMissingReason.incompleteRecording,
        sizeBytes: 0,
      ),
      throwsFormatException,
    );
  });
  test(
    'duplicate IDs and incomplete collection cannot silently become complete',
    () {
      expect(
        () => manifest(files: [included(1), included(1)]),
        throwsFormatException,
      );
      final value = manifest(
        online: true,
        files: [
          ExportAudioEntry(
            recordingId: id(1),
            selected: true,
            included: false,
            missingReason: ExportMissingReason.notCollected,
          ),
        ],
      );
      expect(value.collectionFinished, isFalse);
      expect(value.canClaimCompleteOnline, isFalse);
    },
  );
  test(
    'corrupt totals, unknown fields, versions, dates and paths are rejected',
    () {
      final mutations = <void Function(Map<String, Object?>)>[
        (m) => m['included_audio_count'] = 2,
        (m) => m['included_audio_bytes'] = 101,
        (m) => m['schema_version'] = 2,
        (m) => m['schema_version'] = 1.0,
        (m) => m['auth_token'] = 'fixture',
        (m) => m['created_at'] = '2026-02-31T00:00:00Z',
        (m) => m['local_cutoff_at'] = '2026-10-11T00:00:00',
        (m) => m['snapshot_cursor'] = 0,
        (m) => (m['files'] as List).first['relative_path'] = '../private.m4a',
        (m) =>
            (m['files'] as List).first['relative_path'] = 'C:/private/file.m4a',
        (m) =>
            (m['files'] as List).first['relative_path'] = 'audio/${id(2)}.m4a',
        (m) => (m['files'] as List).first['sha256'] = 'invalid',
      ];
      for (final mutate in mutations) {
        final map = manifest().toJson();
        mutate(map);
        expect(
          () => ExportManifest.decode(jsonEncode(map)),
          throwsFormatException,
        );
      }
      expect(
        () => ExportManifest.decode(
          manifest().encode().replaceFirst(
            '"schema_version":1',
            '"schema_version":1,"schema_version":1',
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'file order and returned JSON cannot mutate the frozen specification',
    () {
      final files = [included(2), included(1)];
      final value = manifest(files: files);
      files.clear();
      expect(value.files.first.recordingId, id(1));
      expect(() => value.files.clear(), throwsUnsupportedError);
      ((value.toJson()['files'] as List).first as Map).clear();
      expect(value.files, hasLength(2));
    },
  );
}
