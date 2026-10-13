import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_adapters.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/settings/account_deletion.dart';

class _Vault implements SessionVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _Social implements SocialProofSource {
  @override
  Future<String> proof(String provider) async =>
      throw StateError('No social login in fixture');
}

class _BApi implements AuthApi {
  final AuthSession current;
  _BApi(this.current);
  @override
  Future<String> me(AuthSession session) async => session.userId;
  @override
  Future<AuthSession> refresh(AuthSession session) async => current;
  @override
  Future<AuthSession> login(String provider, String proof) async =>
      throw StateError('No user login');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage(), key = 'p23_08_owned_fixture_v1';
  final raw = await storage.read(key: key);
  final config = raw == null
      ? <String, dynamic>{
          'fixture': UuidValue.random().value,
          'owner': UuidValue.random().value,
          'other': UuidValue.random().value,
          'device': UuidValue.random().value,
          'complete': false,
        }
      : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  for (final name in ['fixture', 'owner', 'other', 'device']) {
    UuidValue(config[name] as String);
  }
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    config['port'] as int? ?? 0,
  );
  config['port'] = server.port;
  await storage.write(key: key, value: jsonEncode(config));
  var deleted = config['complete'] == true;
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    final body = jsonDecode(await utf8.decoder.bind(request).join());
    if (deleted &&
        request.method == 'POST' &&
        request.uri.path == '/v1/account/deletion-device-confirmations' &&
        body['user_id'] == config['owner'] &&
        body['device_id'] == config['device'] &&
        request.headers.value('X-Deletion-Device-Proof') ==
            'sr_r_${'r' * 43}' &&
        request.headers.value('Authorization') == null) {
      request.response.write('{"deletion_confirmed":true}');
    } else {
      request.response.statusCode = 404;
      request.response.write('{}');
    }
    await request.response.close();
  });
  final support = await getApplicationSupportDirectory();
  final root = Directory(
    p.join(support.path, 'p23-08-owned-fixture', config['fixture'] as String),
  );
  await root.create(recursive: true);
  final origin = Uri.parse('http://127.0.0.1:${server.port}');
  final manager = AccountStoreManager(
    environment: AppEnvironment.dev,
    origin: origin,
    directory: () async => root,
  );
  final api = HttpAuthApi(origin, allowLocalHttp: true);
  final a = AuthSession(
    userId: config['owner'] as String,
    deviceId: config['device'] as String,
    accessToken: 'sr_a_${'a' * 43}',
    refreshToken: 'sr_r_${'r' * 43}',
    accessExpiresAt: DateTime.utc(2099),
    refreshExpiresAt: DateTime.utc(2099),
  );
  Future<List<String>> verify() async {
    final results = <String>[];
    String ownerPath(String id) =>
        p.join(root.path, 'song_record', 'dev', 'accounts', id);
    final owner = config['owner'] as String, other = config['other'] as String;
    final external = File(p.join(root.path, 'external-export.zip'));
    const receiptVault = SecureDeletionReceiptVault();
    final receiptScope = 'p23-08:${origin.origin}:$owner';
    if (config['complete'] == true) {
      await manager.recoverConfirmedDeletions();
      var blocked = false;
      try {
        await manager.openAccount(owner);
      } catch (_) {
        blocked = true;
      }
      if (!blocked || await Directory(ownerPath(owner)).exists()) {
        throw StateError('Deleted owner reopened');
      }
      (await manager.openAccount(other)).requireActive();
      if (!await external.exists() ||
          await receiptVault.read(receiptScope) == null) {
        throw StateError('Preserved proof/export missing');
      }
      await manager.logout();
      return ['재시작 삭제 차단: PASS', '다른 계정 DB 보존: PASS', '외부 사본·확인증 보존: PASS'];
    }
    await manager.openAccount(owner);
    final audio = File(
      p.join(ownerPath(owner), 'audio', '${UuidValue.random().value}.m4a'),
    );
    await audio.writeAsString('synthetic A audio');
    await external.writeAsString('synthetic independent copy');
    final b = await manager.openAccount(other);
    final bAudio = File(
      p.join(ownerPath(other), 'audio', '${UuidValue.random().value}.m4a'),
    );
    await bAudio.writeAsString('synthetic B audio');
    final receipt = DeletionReceipt(
      receiptScope,
      UuidValue.random().value,
      't' * 43,
      UuidValue.random().value,
      1,
      DateTime.now().toUtc().add(const Duration(minutes: 10)),
      UuidValue.random().value,
    );
    await receiptVault.write(receiptScope, jsonEncode(receipt.toJson()));
    if (await api.confirmDeletion(a) != null || !await audio.exists()) {
      throw StateError('Unconfirmed request removed data');
    }
    results.add('서버 미확인 시 보존: PASS');
    deleted = true;
    final proof = await api.confirmDeletion(a);
    if (proof == null) throw StateError('Device proof failed');
    final bs = AuthSession(
      userId: other,
      deviceId: owner,
      accessToken: 'synthetic',
      refreshToken: 'synthetic',
      accessExpiresAt: DateTime.utc(2099),
      refreshExpiresAt: DateTime.utc(2099),
    );
    final vault = _Vault()..value = jsonEncode(bs.toJson());
    final controller = AuthController(
      api: _BApi(bs),
      vault: vault,
      proofs: _Social(),
      openAccount: (_) async {},
      closeAccount: () async {
        throw StateError('A deletion closed B');
      },
      deleteAccountFiles: manager.applyConfirmedDeletion,
    );
    await controller.restore();
    await controller.applyConfirmedDeletion(proof);
    if (await Directory(ownerPath(owner)).exists()) {
      throw StateError('A files remain');
    }
    results.add('A DB·개인 음원 삭제: PASS');
    b.requireActive();
    if (controller.session?.userId != other ||
        await bAudio.readAsString() != 'synthetic B audio') {
      throw StateError('B changed');
    }
    results.add('활성 B 계정 보존: PASS');
    if (await external.readAsString() != 'synthetic independent copy') {
      throw StateError('External copy changed');
    }
    results.add('앱 밖 사본 유지: PASS');
    if (await receiptVault.read(receiptScope) != jsonEncode(receipt.toJson())) {
      throw StateError('Protected receipt changed');
    }
    results.add('암호화 확인증 유지: PASS');
    await manager.applyConfirmedDeletion(proof);
    results.add('삭제 재적용 멱등성: PASS');
    await manager.logout();
    var blocked = false;
    try {
      await manager.openAccount(owner);
    } catch (_) {
      blocked = true;
    }
    if (!blocked) throw StateError('Deleted UUID recreated');
    results.add('삭제 UUID 재생성 차단: PASS');
    controller.dispose();
    config['complete'] = true;
    await storage.write(key: key, value: jsonEncode(config));
    return results;
  }

  runApp(MaterialApp(theme: AppTheme.dark(), home: _Screen(verify)));
}

class _Screen extends StatefulWidget {
  const _Screen(this.verify);
  final Future<List<String>> Function() verify;
  @override
  State<_Screen> createState() => _State();
}

class _State extends State<_Screen> {
  List<String> results = [];
  bool busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P23-08 계정별 삭제 검증')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '새 합성 계정·별도 시험 DB/파일·로컬 HTTP 증명. 개인 계정/녹음 삭제 없음. 실제 R2·MySQL 검사는 PC의 별도 시험 근거로 확인합니다.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      results = [];
                    });
                    try {
                      final value = await widget.verify();
                      if (mounted) setState(() => results = value);
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => results = ['검사 실패 — 시험 기록 보존. AI가 원인 확인'],
                        );
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('검증 시작'),
          ),
          if (busy) const LinearProgressIndicator(),
          for (final value in results)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(value),
            ),
        ],
      ),
    ),
  );
}
