import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/settings/settings_api.dart';
import 'package:song_record/features/settings/storage_request_outbox.dart';
import 'package:song_record/features/settings/storage_request_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const id = '11111111-1111-4111-8111-111111111111';
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final state = _ServerState();
  server.listen((r) async {
    r.response.headers.contentType = ContentType.json;
    if (r.headers.value('Authorization') != 'Bearer synthetic' ||
        r.headers.value('X-Device-Id') != id) {
      r.response.statusCode = 401;
    } else if (!state.online) {
      r.response.statusCode = 503;
    } else if (r.method == 'GET') {
      r.response.write(
        jsonEncode({
          'items': state.receipts.values.toList(),
          'next_cursor': null,
          'count': state.receipts.length,
        }),
      );
    } else {
      final body =
          jsonDecode(await utf8.decoder.bind(r).join()) as Map<String, dynamic>;
      final receipt = state.receipts.putIfAbsent(
        body['id'] as String,
        () => {
          ...body,
          'status': 'RECEIVED',
          'revision': 1,
          'received_at': '2026-10-12T00:00:00Z',
          'updated_at': '2026-10-12T00:00:00Z',
        },
      );
      if (state.loseNext) {
        state.loseNext = false;
        r.response.statusCode = 503;
      } else {
        r.response.statusCode = 201;
        r.response.write(jsonEncode(receipt));
      }
    }
    await r.response.close();
    state.changed();
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
  const scope = 'p23-verification-demand:$id';
  final box = StorageRequestOutbox(
    scope: scope,
    vault: SecureDemandVault(scope),
    send: api.sendStorageRequest,
    requireCurrent: () {},
  );
  runApp(_App(state, box, api));
  await box.initialize();
}

class _ServerState extends ChangeNotifier {
  bool online = false, loseNext = false;
  final receipts = <String, Map<String, dynamic>>{};
  void changed() => notifyListeners();
}

class _App extends StatelessWidget {
  const _App(this.state, this.box, this.api);
  final _ServerState state;
  final StorageRequestOutbox box;
  final SettingsApi api;
  Future<List<Map<String, dynamic>>> history() async =>
      ((await api.storageRequestsPage())['items'] as List)
          .cast<Map<String, dynamic>>();
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      appBar: AppBar(title: const Text('P23-04 보관 요청 검증')),
      body: Column(
        children: [
          const Text('합성 HTTP · 암호화 대기열만 검증 앱 기기 저장'),
          ListenableBuilder(
            listenable: state,
            builder: (c, _) => Wrap(
              children: [
                TextButton(
                  onPressed: () {
                    state.online = !state.online;
                    state.changed();
                  },
                  child: Text(state.online ? '연결됨 → 오프라인' : '오프라인 → 연결'),
                ),
                TextButton(
                  onPressed: () {
                    state.loseNext = true;
                    state.changed();
                  },
                  child: const Text('다음 응답 유실'),
                ),
                Text('합성 서버 접수 ${state.receipts.length}건'),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: box,
            builder: (c, _) => Text(
              '기기 대기 ${box.items.length}건 · ${box.items.map((i) => (i['id'] as String).substring(0, 8)).join(',')}',
            ),
          ),
          Expanded(
            child: StorageRequestScreen(outbox: box, loadHistory: history),
          ),
        ],
      ),
    ),
  );
}
