import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/identity_link.dart';
import 'package:song_record/features/settings/account_deletion.dart';
import 'package:song_record/features/settings/account_deletion_screen.dart';

class _NoProof implements IdentityLinkProofSource {
  @override
  Future<String> linkProof(String provider, String nonce) async =>
      throw StateError('Read-only synthetic status');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const prep = '77777777-7777-4777-8777-777777777777';
  const scope = 'p23-07-installation-synthetic:$prep';
  var state = 'BACKUP_CLEANUP', failed = false;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final now = DateTime.now().toUtc(),
      accepted = DateTime.now().toUtc().subtract(const Duration(days: 8));
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    if (failed) {
      request.response.statusCode = 503;
    } else if (request.method != 'GET' ||
        request.uri.path != '/v1/account/deletion-status/$prep' ||
        request.headers.value('X-Deletion-Status-Token') != 'v' * 43 ||
        request.headers.value('Authorization') != null) {
      request.response.statusCode = 404;
    } else {
      request.response.write(
        jsonEncode({
          'status': state,
          'retrying': state == 'BACKUP_CLEANUP',
          'accepted_at': accepted.toIso8601String(),
          'service_deleted_at': {'BACKUP_CLEANUP', 'COMPLETED'}.contains(state)
              ? accepted.add(const Duration(days: 1)).toIso8601String()
              : null,
          'backup_purge_due_at': accepted
              .add(const Duration(days: 7))
              .toIso8601String(),
          'completed_at': state == 'COMPLETED' ? now.toIso8601String() : null,
          'expires_at': accepted
              .add(const Duration(days: 30))
              .toIso8601String(),
        }),
      );
    }
    await request.response.close();
  });
  const vault = SecureDeletionReceiptVault();
  if (await vault.read(scope) == null) {
    final receipt = DeletionReceipt(
      scope,
      prep,
      'v' * 43,
      prep,
      1,
      now.add(const Duration(minutes: 10)),
      prep,
    );
    await vault.write(scope, jsonEncode(receipt.toJson()));
  }
  final api = AccountDeletionApi(
    Uri.parse('http://127.0.0.1:${server.port}'),
    () => throw StateError('No normal login'),
    () => throw StateError('No deletion commands'),
    local: true,
  );
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        appBar: AppBar(title: const Text('P23-07 삭제 상태 검증')),
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  '합성 상태 응답·검증 전용 확인증. 개인 계정/DB/R2 삭제 없음. 선택 후 아래 상태 확인 버튼으로 조회합니다.',
                ),
              ),
              Wrap(
                children: [
                  for (final entry in {
                    'ACCEPTED': '접수',
                    'DELETING': '삭제 중',
                    'BACKUP_CLEANUP': '백업 지연·재시도',
                    'COMPLETED': '완료',
                  }.entries)
                    TextButton(
                      onPressed: () {
                        state = entry.key;
                        failed = false;
                      },
                      child: Text(entry.value),
                    ),
                  TextButton(
                    onPressed: () {
                      failed = true;
                    },
                    child: const Text('서버 실패'),
                  ),
                ],
              ),
              Expanded(
                child: AccountDeletionScreen(
                  flow: AccountDeletionFlow(scope, api, _NoProof(), vault),
                  statusOnly: true,
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
