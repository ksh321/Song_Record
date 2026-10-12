import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/settings/accent_preferences.dart';
import 'package:song_record/features/settings/classification_screen.dart';
import 'package:song_record/features/settings/settings_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const id = '11111111-1111-4111-8111-111111111111';
  final tags = <Map<String, dynamic>>[
    {'id': id, 'name': '합성 태그', 'revision': 1, 'archived_at': null},
  ];
  final conditions = [
    for (final pair in [
      ('VERY_GOOD', '매우 좋음'),
      ('GOOD', '좋음'),
      ('NORMAL', '보통'),
      ('BAD', '안 좋음'),
    ])
      {'code': pair.$1, 'name': pair.$2},
  ];
  final receipts = <String, Map<String, dynamic>>{};
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((r) async {
    r.response.headers.contentType = ContentType.json;
    if (r.headers.value('Authorization') != 'Bearer synthetic' ||
        r.headers.value('X-Device-Id') != id) {
      r.response.statusCode = 401;
    } else if (r.method == 'GET') {
      r.response.write(
        jsonEncode(
          r.uri.path == '/v1/conditions'
              ? {'items': conditions}
              : {'items': tags, 'next_cursor': null, 'count': tags.length},
        ),
      );
    } else {
      final op = r.headers.value('Idempotency-Key');
      final body = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      if (op == null) {
        r.response.statusCode = 400;
      } else if (receipts.containsKey(op)) {
        r.response.write(jsonEncode(receipts[op]));
      } else {
        Map<String, dynamic>? answer;
        if (r.method == 'POST' && r.uri.path == '/v1/tags') {
          answer = {
            'id': body['id'],
            'name': body['name'],
            'revision': 1,
            'archived_at': null,
          };
          tags.add(answer);
        } else {
          final index = tags.indexWhere(
            (t) => t['id'] == r.uri.pathSegments[2],
          );
          if (index < 0 || tags[index]['revision'] != body['base_revision']) {
            r.response.statusCode = 409;
          } else {
            answer = {
              ...tags[index],
              'revision': (tags[index]['revision'] as int) + 1,
              if (r.uri.path.endsWith('/archive'))
                'archived_at': '2026-10-12T00:00:00Z'
              else
                'name': body['name'],
            };
            tags[index] = answer;
          }
        }
        if (answer != null) {
          receipts[op] = answer;
          r.response.write(jsonEncode(answer));
        }
      }
    }
    await r.response.close();
  });
  final api = SettingsApi(
    Uri.parse('http://localhost:${server.port}'),
    () async => AuthSession(
      userId: id,
      deviceId: id,
      accessToken: 'synthetic',
      refreshToken: 'synthetic',
      accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
    ),
    () {},
    local: true,
  );
  const preferences = DeviceAccentPreferences();
  final accent = ValueNotifier(await preferences.read() ?? AppAccent.initial);
  runApp(_Verification(api, accent, preferences));
}

class _Verification extends StatelessWidget {
  const _Verification(this.api, this.accent, this.preferences);
  final SettingsApi api;
  final ValueNotifier<AppAccent> accent;
  final AccentPreferences preferences;
  Future<ClassificationData> load() async => (
    tags: ((await api.tagsPage())['items'] as List)
        .cast<Map<String, dynamic>>(),
    conditions: ((await api.get('/v1/conditions'))['items'] as List)
        .cast<Map<String, dynamic>>(),
  );
  Future<void> command(
    String m,
    String p,
    Map<String, Object?> b,
    String op,
  ) async {
    await api.tagCommand(m, p, b, op);
  }

  Future<void> save(AppAccent a) async {
    await preferences.write(a);
    accent.value = a;
  }

  @override
  Widget build(BuildContext c) => ValueListenableBuilder<AppAccent>(
    valueListenable: accent,
    builder: (c, value, _) => MaterialApp(
      theme: AppTheme.dark(accent: value),
      home: Scaffold(
        appBar: AppBar(title: const Text('P23-03 개인화·태그 검증')),
        body: Column(
          children: [
            const Text('태그 합성 HTTP · 강조색만 검증 앱 기기 저장'),
            Expanded(
              child: ClassificationScreen(
                load: load,
                command: command,
                requireCurrent: () {},
                accent: accent,
                saveAccent: save,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
