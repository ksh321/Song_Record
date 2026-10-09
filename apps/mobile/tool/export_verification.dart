import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/files/recording_export.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/recording_export_button.dart';

import 'local_preservation_fixture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(theme: AppTheme.dark(), home: const ExportCheck()));
}

class ExportCheck extends StatefulWidget {
  const ExportCheck({super.key});
  @override
  State<ExportCheck> createState() => _State();
}

class _State extends State<ExportCheck> {
  final manager = AccountStoreManager(environment: AppEnvironment.dev);
  RecordingExport? exporter;
  String result = '준비 중';
  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    try {
      final owner = preservationId(0x1401);
      final store = await manager.openAccount(owner);
      await store.readLocalAudio(preservationId(0x1402));
      await const MethodChannel('song_record/account').invokeMethod<void>(
        'setAccount',
        {'userId': owner, 'environment': 'dev'},
      );
      exporter = RecordingExport(store);
      result = '완료된 입력 대기 합성 M4A · 준비 완료';
    } catch (_) {
      result = '준비 실패';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P14-06 M4A 내보내기 검증')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(result),
          const Text(
            '같은 위치에 2회 저장하여 중복 이름을 확인하고 3회째는 취소하세요. 저장된 합성 음도 재생해 주세요.',
          ),
          if (exporter != null)
            RecordingExportButton(
              exporter: exporter!,
              recordingId: preservationId(0x1402),
              title: 'P14-06 합성_곡',
              artist: '테스트_가수',
            ),
        ],
      ),
    ),
  );
}
