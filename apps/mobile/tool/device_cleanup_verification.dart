import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/files/device_file_cleanup.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/device_file_cleanup_button.dart';

import 'local_preservation_fixture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(theme: AppTheme.dark(), home: const CleanupCheck()));
}

class CleanupCheck extends StatefulWidget {
  const CleanupCheck({super.key});
  @override
  State<CleanupCheck> createState() => _State();
}

class _State extends State<CleanupCheck> {
  final manager = AccountStoreManager(environment: AppEnvironment.dev);
  final owner = preservationId(0x1401), id = preservationId(0x1471);
  AccountStore? store;
  DeviceFileCleanup? flow;
  String result = '준비 중';
  String? original;
  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    try {
      store = await manager.openAccount(owner);
      final asset = await rootBundle.load(
        'assets/verification/playback-tone.m4a',
      );
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final hash = sha256.convert(bytes).toString();
      await store!.preserveDownloadedAudio(
        owner,
        id,
        hash,
        bytes.length,
        bytes,
      );
      if (await store!.readMetadata(LocalEntity.recording, id) == null) {
        await store!.saveEdit(
          LocalEdit(
            opId: preservationId(0x1472),
            entity: LocalEntity.recording,
            entityId: id,
            operation: LocalOperation.create,
            baseRevision: 0,
            draft: {'title': 'P14-07 synthetic', 'lifecycle_state': 'ACTIVE'},
            changes: {'title': 'P14-07 synthetic'},
          ),
        );
      }
      original = (await store!.readMetadata(
        LocalEntity.recording,
        id,
      ))!.localJson;
      flow = DeviceFileCleanup(store!);
      final preview = await flow!.preview(id);
      final token = preservationId(DateTime.now().millisecondsSinceEpoch), gen = preservationId(0x1473);
      await store!.beginLocalCleanupFence(
        token: token,
        owner: owner,
        recording: id,
        generation: gen,
        checksum: hash,
        size: bytes.length,
        revision: 1,
        expires: DateTime.now().toUtc().add(const Duration(minutes: 14)),
      );
      var blocked = false;
      try {
        await flow!.confirm(preview, confirmed: true, lossAcknowledged: true);
      } catch (_) {
        blocked = true;
      }
      if (!blocked || (await store!.readLocalAudio(id)).length != bytes.length) {
        throw StateError('Fence lost');
      }
      await store!.finishLocalCleanupFence(token, gen, 'CANCELLED');
      result = '정리 보호 검사 통과 · 합성 파일만 준비 완료';
    } catch (_) {
      result = '준비 실패';
      flow = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> check() async {
    final file = await store!.findPlayableLocalAudio(id);
    final unchanged =
        (await store!.readMetadata(LocalEntity.recording, id))!.localJson ==
        original;
    setState(
      () => result = file == null && unchanged
          ? 'P14-07 파일만 제거·녹음 정보 유지 통과'
          : file != null && unchanged
          ? 'P14-07 파일·녹음 정보 유지 (취소 확인)'
          : 'P14-07 검사 실패',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P14-07 이 기기 파일 정리 검증')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(result),
          const Text(
            '이번 P14-07 전용 합성 파일만 정리합니다. 이전 재생·다운로드 원본과 개인 파일은 대상이 아닙니다.',
          ),
          if (flow != null)
            DeviceFileCleanupButton(cleanup: flow!, recordingId: id),
          if (flow != null)
            OutlinedButton(onPressed: check, child: const Text('결과 확인')),
        ],
      ),
    ),
  );
}
