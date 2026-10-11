import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_job.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/export/export_zip.dart';

const owner = '21212121-2121-4121-8121-212121212121';
const jobId = '21212121-2121-4121-8121-212121212107';
const recording = '21212121-2121-4121-8121-212121212106';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Verification only');
  }
  await const MethodChannel(
    'song_record/account',
  ).invokeMethod<void>('setAccount', {'userId': owner, 'environment': 'dev'});
  final store = await AccountStoreManager(environment: AppEnvironment.dev)
      .openAccount(owner);
  final now = DateTime.now().toUtc();
  final bytes = (await rootBundle.load('assets/verification/playback-tone.m4a'))
      .buffer
      .asUint8List();
  final hash = sha256.convert(bytes).toString();
  final baseline = ExportBaseline(
    id: jobId,
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
      'snapshot_rows': [],
      'changes': [],
      'recording_inputs': [],
      'copies': [
        {
          'entity_type': 'RECORDING',
          'entity_id': recording,
          'server_revision': 0,
          'tombstone': 0,
          'server_payload': null,
          'local_payload': jsonEncode({
            'id': recording,
            'title_snapshot': '백업 합성 음',
            'artist_snapshot': '시험 자료',
            'lifecycle_state': 'ACTIVE',
            'metadata_state': 'SAVED',
            'note': '개인 자료 없는 시험',
          }),
        },
      ],
    },
  );
  var data = ExportData.fromBaseline(baseline);
  var manifest = ExportManifest.fromBaseline(
    baseline,
    metadataCount: data.metadataCount,
    files: [
      ExportAudioEntry(
        recordingId: recording,
        selected: true,
        included: true,
        missingReason: null,
        sha256: hash,
        sizeBytes: bytes.length,
        durationMs: 1000,
      ),
    ],
  );
  await store.stageExportAudio(jobId, recording, hash, bytes.length, bytes);
  final job = ExportJob(
    owner: owner,
    id: jobId,
    file: (name) => store.privateExportFile(jobId, name),
    requireCurrent: store.requireActive,
  );
  // Reopening the app validates the existing job; it never clears this account.
  ExportZip? zip;
  var status = '새 ZIP 준비 완료';
  if (await (await store.privateExportFile(
    jobId,
    'checkpoint.json',
  )).exists()) {
    try {
      final resumed = await job.resume();
      zip = resumed.zip;
      data = resumed.data;
      manifest = resumed.manifest;
      status = '기존 작업 해시 확인·재개 완료';
    } catch (_) {
      status = '기존 작업 손상 · 이전 ZIP 보존';
    }
  }
  zip ??= await ExportZipWriter(
    file: job.file,
    requireCurrent: store.requireActive,
  ).write(data, manifest);
  await job.save(data, manifest, zip: zip);
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: BackupCheck(
        zip: zip,
        status: status,
        job: job,
        data: data,
        manifest: manifest,
      ),
    ),
  );
}

class BackupCheck extends StatefulWidget {
  const BackupCheck({
    required this.zip,
    required this.status,
    required this.job,
    required this.data,
    required this.manifest,
    super.key,
  });
  final ExportZip zip;
  final String status;
  final ExportJob job;
  final ExportData data;
  final ExportManifest manifest;
  @override
  State<BackupCheck> createState() => _State();
}

class _State extends State<BackupCheck> {
  bool busy = false;
  String? result;
  Future<void> save() async {
    setState(() {
      busy = true;
    });
    try {
      final saved = await const AndroidBackupDestination().save(
        widget.zip,
        owner: owner,
        environment: 'dev',
        jobId: jobId,
      );
      await widget.job.save(
        widget.data,
        widget.manifest,
        zip: widget.zip,
        externallySaved: saved,
      );
      result = saved ? '앱 밖 ZIP 저장·전체 체크섬 확인 완료' : '저장 취소 · 내부 ZIP과 합성 원본 보존';
    } catch (_) {
      result = '저장 실패 · 내부 ZIP 보존 · 외부 미완성 사본 가능';
    }
    if (mounted) {
      setState(() {
        busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P21-07 ZIP 저장 검증')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('별도 시험 계정 · 합성 음 1개 · 개인 계정 변경 없음'),
          Text(widget.status),
          const SizedBox(height: 16),
          const Text(backupPrivacyNotice),
          const SizedBox(height: 16),
          Text(result ?? '포함 정보 1개 · 합성 파일 1개'),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('시험 ZIP 저장'),
          ),
        ],
      ),
    ),
  );
}
