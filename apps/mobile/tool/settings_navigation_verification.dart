import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/settings/settings_api.dart';
import 'package:song_record/features/settings/settings_read_screen.dart';
import 'package:song_record/features/settings/settings_screen.dart';

class _AccountChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await const MethodChannel('song_record/account').invokeMethod<void>(
    'setAccount',
    {'userId': '11111111-1111-4111-8111-111111111111', 'environment': 'dev'},
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.headers.value('Authorization') != 'Bearer synthetic' ||
        request.headers.value('X-Device-Id') !=
            '00000000-0000-4000-8000-000000000001') {
      request.response.statusCode = 401;
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'value': request.uri.path == '/v1/storage' ? '197' : '합성 분류 이름',
        }),
      );
    }
    await request.response.close();
  });
  final changes = _AccountChanges();
  var active = true;
  void guard() {
    if (!active) throw StateError('Account switched');
  }

  final api = SettingsApi(
    Uri.parse('http://localhost:${server.port}'),
    () async => AuthSession(
      userId: '11111111-1111-4111-8111-111111111111',
      deviceId: '00000000-0000-4000-8000-000000000001',
      accessToken: 'synthetic',
      refreshToken: 'synthetic',
      accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
    ),
    guard,
    local: true,
  );
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        appBar: AppBar(title: const Text('P23-01 설정 탐색 검증')),
        body: Column(
          children: [
            const Text('합성 HTTP 응답 · 개인 계정/서버 값 아님'),
            Expanded(
              child: SettingsScreen(
                showDevelopmentTools: false,
                storageBuilder: (_) => SettingsReadScreen(
                  title: '보관량과 고정',
                  accountChanges: changes,
                  requireCurrent: guard,
                  load: () async => [
                    (
                      '합성 서버 응답',
                      (await api.get('/v1/storage'))['value'] as String,
                    ),
                  ],
                ),
                classificationBuilder: (_) => SettingsReadScreen(
                  title: '개인화와 분류 관리',
                  accountChanges: changes,
                  requireCurrent: guard,
                  load: () async => [
                    ('합성 태그', (await api.get('/v1/tags'))['value'] as String),
                  ],
                ),
                importBuilder: (_) => const _Picker(),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            active = false;
            changes.changed();
          },
          label: const Text('계정 전환 시험'),
        ),
      ),
    ),
  );
}

class _Picker extends StatefulWidget {
  const _Picker();
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String result = '실제 문서 선택 창에서 취소만 검사합니다.';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('백업 가져오기')),
    body: SafeArea(
      child: Column(
        children: [
          Text(result),
          FilledButton(
            onPressed: () async {
              try {
                final value = await const MethodChannel(
                  'song_record/backup_import',
                ).invokeMethod<String>('pickZip');
                if (mounted) {
                  setState(
                    () => result = value == null
                        ? '선택 취소 정상 · 기존 파일 변경 없음'
                        : '파일 읽기 완료',
                  );
                }
              } catch (_) {
                if (mounted) setState(() => result = '선택 검사 실패');
              }
            },
            child: const Text('문서 선택 취소 검사'),
          ),
        ],
      ),
    ),
  );
}
