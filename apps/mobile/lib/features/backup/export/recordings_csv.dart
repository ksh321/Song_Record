import 'dart:convert';
import 'dart:typed_data';

import '../../../core/domain/song_types.dart';
import 'export_data.dart';
import 'export_manifest.dart';

/// RFC 4180 cell with spreadsheet formula neutralization. Preserve the original
/// text (including newlines) after the protective apostrophe; data.json is exact.
String backupCsvCell(String text) {
  final leading = RegExp(r'^[\s\x00-\x1f\ufeff]*').firstMatch(text)!.end;
  final rest = text.substring(leading);
  final dangerous =
      text.startsWith('\t') ||
      text.startsWith('\r') ||
      text.startsWith('\n') ||
      rest.isNotEmpty && '=+-@'.contains(rest[0]);
  final safe = dangerous ? "'$text" : text;
  return '"${safe.replaceAll('"', '""')}"';
}

String _text(Object? value) => value == null ? '' : value.toString();
String _version(Object? value) {
  for (final version in VersionCode.values) {
    if (version.name.toUpperCase() == value) return formatVersionCode(version);
  }
  return _text(value);
}

String _key(Map<String, dynamic> recording) {
  final mode = recording['key_mode'], shift = recording['key_shift'];
  if (shift is int && shift >= -12 && shift <= 12) {
    for (final key in KeyMode.values) {
      if (key.name.toUpperCase() == mode) {
        return formatMusicalKey(MusicalKey(mode: key, shift: shift));
      }
    }
  }
  return '미정';
}

/// Human CSV is a view of the same frozen export, not the import source.
/// Inclusion is taken from final manifest proof, never guessed from cloud state.
Uint8List recordingsCsv(ExportData data, ExportManifest manifest) {
  final json = data.toJson();
  if (json['export_id'] != manifest.exportId ||
      json['source_user_id'] != manifest.sourceUserId ||
      data.metadataCount != manifest.metadataCount ||
      !manifest.collectionFinished) {
    throw const FormatException('CSV requires the collected export manifest');
  }
  final songs = <String, Map<String, dynamic>>{},
      recordings = <Map<String, dynamic>>[];
  for (final record in data.records) {
    final payload = record['payload'] as Map<String, dynamic>;
    if (record['entity'] == 'SONG') {
      songs[record['resource_id'] as String] = payload;
    }
    if (record['entity'] == 'RECORDING') {
      recordings.add({
        ...payload,
        'id': record['resource_id'],
        '_tombstone': record['tombstone'],
      });
    }
  }
  recordings.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  final files = {for (final file in manifest.files) file.recordingId: file};
  final inputs = {
    for (final input in json['recording_inputs'] as List)
      input['recording_id'] as String: input as Map<String, dynamic>,
  };
  final rows = <List<String>>[
    [
      '녹음 ID',
      '곡명',
      '가수',
      '버전',
      '키',
      '녹음 시각',
      '시간대',
      '티어',
      '메모',
      '파일 포함',
      '미포함 사유',
      '정보 상태',
      '삭제 상태',
    ],
  ];
  for (final recording in recordings) {
    final id = recording['id'] as String, song = songs[recording['song_id']];
    final input = inputs[id]?['input_form'];
    final draft =
        recording['metadata_state'] == 'DRAFT' && input is Map<String, dynamic>;
    final view = <String, dynamic>{...recording, if (draft) ...input};
    final file = files[id];
    rows.add([
      id,
      _text(view['title_snapshot'] ?? song?['title']),
      _text(view['artist_snapshot'] ?? song?['artist']),
      _version(view['version_code']),
      _key(view),
      _text(view['recorded_at']),
      _text(view['timezone_id']),
      _text(view['tier']),
      _text(view['note']),
      file?.included == true ? '포함' : '미포함',
      file?.missingReason?.wire ?? (file == null ? '명세 없음' : ''),
      draft
          ? '입력 대기 · 미저장 입력 포함'
          : recording['metadata_state'] == 'DRAFT'
          ? '입력 대기'
          : '저장됨',
      recording['_tombstone'] == true
          ? '영구 삭제 표식'
          : _text(recording['lifecycle_state']),
    ]);
  }
  // UTF-8 BOM lets Excel display Korean correctly; quoted CRLF records preserve
  // commas, quotes and multiline memos without creating additional CSV columns.
  return Uint8List.fromList(
    utf8.encode(
      '\ufeff${rows.map((r) => r.map(backupCsvCell).join(',')).join('\r\n')}\r\n',
    ),
  );
}
