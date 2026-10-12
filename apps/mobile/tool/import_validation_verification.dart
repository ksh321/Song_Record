import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/export/export_zip.dart';
import 'package:song_record/features/backup/import/import_validation.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

// Synthetic 1-second 440Hz AAC-LC / 48kHz / mono; contains no user recording.
const tone =
    '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';
const owner = '00000000-0000-4000-8000-000000002201';
const recording = '00000000-0000-4000-8000-000000002202';
const exportId = '00000000-0000-4000-8000-000000002203';
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(theme: AppTheme.dark(), home: const ImportCheck()));
}

class ImportCheck extends StatefulWidget {
  const ImportCheck({super.key});
  @override
  State<ImportCheck> createState() => _State();
}

class _State extends State<ImportCheck> {
  String result = '검사 준비 중';
  String stage = 'PREPARE';
  @override
  void initState() {
    super.initState();
    run();
  }

  Future<void> run() async {
    final cache = await getTemporaryDirectory();
    final root = await cache.createTemp('import-p22-03-');
    final documents = await getApplicationSupportDirectory();
    final external = await documents.createTemp('import-path-check-');
    try {
      final probe = AndroidImportAudioProbe();
      final bytes = base64Decode(tone);
      final original = File('${root.path}/original.m4a');
      await original.writeAsBytes(bytes);
      stage = 'FULL_DECODE';
      final actual = await probe.inspect(original);
      if (actual['sample_rate'] != 48000 ||
          actual['channels'] != 1 ||
          actual['aac_profile'] != 2) {
        throw StateError('format');
      }
      final now = DateTime.utc(2026, 10, 12);
      final spec = {
        'sha256': sha256.convert(bytes).toString(),
        'size_bytes': bytes.length,
        'duration_ms': actual['duration_ms'],
        'codec': 'AAC_LC',
        'sample_rate': 48000,
        'channels': 1,
        'capture_integrity': 'VALIDATED',
      };
      final baseline = ExportBaseline(
        id: exportId,
        owner: owner,
        includeTrash: false,
        manifest: null,
        createdAt: now,
        entries: const [],
        local: {
          'source_user_id': owner,
          'local_cutoff_at': now.toIso8601String(),
          'baseline': [
            {
              'baseline_complete': 0,
              'last_change_seq': null,
              'updated_at': null,
            },
          ],
          'copies': [
            {
              'entity_type': 'RECORDING',
              'entity_id': recording,
              'server_revision': 0,
              'tombstone': 0,
              'server_payload': null,
              'local_payload': jsonEncode({
                'id': recording,
                'song_id': null,
                'title_snapshot': '합성 검사',
                'artist_snapshot': '검사',
                'file': spec,
              }),
            },
          ],
          'changes': [],
          'recording_inputs': [],
        },
      );
      final data = ExportData.fromBaseline(baseline);
      final manifest = ExportManifest.fromBaseline(
        baseline,
        metadataCount: data.metadataCount,
        files: [
          ExportAudioEntry(
            recordingId: recording,
            selected: true,
            included: true,
            missingReason: null,
            sha256: spec['sha256'] as String,
            sizeBytes: bytes.length,
            durationMs: actual['duration_ms'] as int,
          ),
        ],
      );
      Future<File> file(String name) async {
        final f = File('${root.path}/export/$name');
        await f.parent.create(recursive: true);
        return f;
      }

      await (await file(manifest.files.single.relativePath!))
          .writeAsBytes(bytes);
      final zip = await ExportZipWriter(
        file: file,
        requireCurrent: () {},
      ).write(data, manifest);
      final staged = await ImportZipReader(
        requireCurrent: () {},
        availableBytes: () async => (await const MethodChannel(
          'com.ksh321.songrecord/recorder_commands',
        ).invokeMethod<num>('availableBackupBytes'))!.toInt(),
      ).unpack(zip.file, root);
      stage = 'ZIP_VALIDATION';
      final validator = ImportValidator(
        owner: owner,
        requireCurrent: () {},
        audio: probe,
      );
      if (!(await validator.verify(staged)).wholeBackupValid) {
        throw StateError('roundtrip');
      }
      stage = 'HASH_CORRUPTION';
      final changed = staged.file(manifest.files.single.relativePath!);
      final bad = bytes.toList();
      bad[bad.length - 1] ^= 1;
      await changed.writeAsBytes(bad);
      if ((await validator.verify(staged)).issues.single.code !=
          'AUDIO_HASH_OR_SIZE') {
        throw StateError('hash');
      }
      stage = 'TRUNCATED';
      final broken = File('${root.path}/broken.m4a');
      await broken.writeAsBytes(bytes.take(24).toList());
      var rejected = false;
      try {
        await probe.inspect(broken);
      } on PlatformException {
        rejected = true;
      }
      if (!rejected) throw StateError('truncated');
      stage = 'OUTSIDE_CACHE';
      final outside = File('${external.path}/tone.m4a');
      await outside.writeAsBytes(bytes);
      rejected = false;
      try {
        await probe.inspect(outside);
      } on PlatformException {
        rejected = true;
      }
      if (!rejected ||
          sha256.convert(await original.readAsBytes()).toString() !=
              spec['sha256']) {
        throw StateError('path');
      }
      result = '4개 모두 통과\n실제 AAC 전체 디코딩·ZIP 전체 검증\n해시 손상 차단·잘린 파일 거절\n임시 경로 밖 거절·원본 보존\n합성 음원 / 로그인·사용자 DB·서버 호출 없음';
    } catch (_) {
      result = '검사 실패: $stage';
    } finally {
      if (path.isWithin(
        await cache.resolveSymbolicLinks(),
        await root.resolveSymbolicLinks(),
      )) {
        await root.delete(recursive: true);
      }
      if (path.isWithin(
        await documents.resolveSymbolicLinks(),
        await external.resolveSymbolicLinks(),
      )) {
        await external.delete(recursive: true);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P22-03 파일 전체 검증')),
    body: SafeArea(
      child: Padding(padding: const EdgeInsets.all(20), child: Text(result)),
    ),
  );
}
