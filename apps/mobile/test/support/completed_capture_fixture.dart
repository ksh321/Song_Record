import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:song_record/core/sync/local_repository.dart';

const owner = '00000000-0000-4000-8000-000000001801';
const other = '00000000-0000-4000-8000-000000001802';
const rec = '00000000-0000-4000-8000-000000001810';
final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
Map<String, dynamic> spec() => {
  'sha256': sha256.convert(bytes).toString(),
  'size_bytes': bytes.length,
  'duration_ms': 12000,
  'codec': 'AAC_LC',
  'sample_rate': 48000,
  'channels': 1,
  'capture_integrity': 'VALIDATED',
};
Future<void> capture(LocalRepository repo, {String? scope, Uint8List? data}) =>
    repo.importCompletedCapture(
      accountScope: scope ?? 'dev/$owner',
      recordingId: rec,
      bytes: data ?? bytes,
      fileSpec: spec(),
      recordedAt: DateTime.utc(2026, 10, 10, 1, 2, 3),
      timezoneId: 'Asia/Seoul',
      timezoneOffsetMinutes: 540,
    );
