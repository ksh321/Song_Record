import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recorder_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Isolated verification only');
  }
  // Own fixture package and account; never assigns legacy/user recordings.
  await const MethodChannel('song_record/account').invokeMethod<void>(
    'setAccount',
    {'userId': '00000000-0000-4000-8000-000000001801', 'environment': 'dev'},
  );
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        appBar: AppBar(title: const Text('P18-01 실제 녹음 검증')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              Text('별도 검증 앱 · 실제 마이크 사용 · 시험 파일은 이 기기에 보존'),
              SizedBox(height: 20),
              RecorderPanel(
                gateway: MethodChannelRecorderGateway(),
                diagnostics: false,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
