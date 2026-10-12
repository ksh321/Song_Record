import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/auth/identity_link.dart';
import 'package:song_record/features/settings/account_deletion.dart';
import 'package:song_record/features/settings/account_deletion_screen.dart';

class _Proof implements IdentityLinkProofSource {
  @override
  Future<String> linkProof(String p, String nonce) async => 'synthetic-proof';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const prep = '33333333-3333-4333-8333-333333333333',
      challenge = '44444444-4444-4444-8444-444444444444';
  const storage = FlutterSecureStorage(),
      serverKey = 'p23_05_synthetic_acceptance';
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((r) async {
    r.response.headers.contentType = ContentType.json;
    r.response.headers.set('Cache-Control', 'no-store');
    Map<String, dynamic> response = {};
    try {
      final path = r.uri.path;
      if (path.contains('/deletion-status/')) {
        if (r.headers.value('X-Deletion-Status-Token') != 't' * 43) {
          r.response.statusCode = 404;
        } else {
          final accepted = await storage.read(key: serverKey) == 'ACCEPTED';
          response = {
            'status': accepted ? 'ACCEPTED' : 'PREPARED',
            'retrying': false,
            'accepted_at': accepted ? '2026-10-12T00:00:00Z' : null,
            'service_deleted_at': null,
            'backup_purge_due_at': accepted ? '2026-10-19T00:00:00Z' : null,
            'completed_at': null,
            'expires_at': accepted ? '2026-11-11T00:00:00Z' : null,
          };
        }
      } else if (r.headers.value('Authorization') != 'Bearer synthetic' ||
          r.headers.value('X-Device-Id') != prep) {
        r.response.statusCode = 401;
      } else if (path.endsWith('reauth-challenges')) {
        response = {
          'challenge_id': challenge,
          'nonce': 'n' * 43,
          'expires_at': '2026-10-12T23:59:59Z',
        };
      } else if (path.endsWith('status-preparations')) {
        response = {
          'preparation_id': prep,
          'status_token': 't' * 43,
          'reauth_proof': challenge,
          'base_revision': 1,
          'prepare_expires_at': '2026-10-12T23:59:59Z',
        };
      } else if (path.endsWith('deletion-requests')) {
        final body = jsonDecode(
          await utf8.decoder.bind(r).join(),
        ) as Map<String, dynamic>;
        if (body['confirmed'] != true ||
            body['scope'] != 'ALL_ACCOUNT_DATA' ||
            r.headers.value('X-Deletion-Status-Token') != 't' * 43) {
          r.response.statusCode = 400;
        } else {
          await storage.write(key: serverKey, value: 'ACCEPTED');
          r.response.statusCode = 503; /* Lost acceptance response: only dedicated status resolves it. */
        }
      } else {
        r.response.statusCode = 404;
      }
      r.response.write(jsonEncode(response));
    } catch (_) {
      r.response.statusCode = 500;
    }
    await r.response.close();
  });
  final api = AccountDeletionApi(
    Uri.parse('http://127.0.0.1:${server.port}'),
    () async => AuthSession(
      userId: prep,
      deviceId: prep,
      accessToken: 'synthetic',
      refreshToken: 'synthetic',
      accessExpiresAt: DateTime.utc(2099),
      refreshExpiresAt: DateTime.utc(2099),
    ),
    () {},
    local: true,
  );
  final flow = AccountDeletionFlow(
    'p23-05-installation-synthetic:$prep',
    api,
    _Proof(),
    const SecureDeletionReceiptVault(),
  );
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        appBar: AppBar(title: const Text('P23-05 탈퇴 접수 검증')),
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '합성 HTTP·합성 소유 확인·검증 전용 암호화 확인증. 개인 계정/DB/R2 삭제 없음. 접수 응답은 고의로 유실하며 확인증 조회로 확인합니다.',
                ),
              ),
              Expanded(
                child: AccountDeletionScreen(
                  flow: flow,
                  onAccepted: () async {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
