import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/account_deletion_confirmation.dart';
import 'package:song_record/features/auth/auth_adapters.dart';
import 'package:song_record/features/auth/auth_session.dart';

class Vault implements SessionVault {
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

class Social implements SocialProofSource {
  @override
  Future<String> proof(String provider) async => 'synthetic';
}

class Aware implements AuthApi, DeletionAwareAuthApi {
  final AuthSession initial;
  Aware(this.initial);
  AccountDeletionConfirmation? result;
  int checks = 0;
  bool rotateReject = false;
  @override
  Future<AccountDeletionConfirmation?> confirmDeletion(
    AuthSession session,
  ) async {
    checks++;
    return result;
  }

  @override
  Future<AuthSession> login(String provider, String proof) async => initial;
  @override
  Future<String> me(AuthSession session) async => session.userId;
  @override
  Future<AuthSession> refresh(AuthSession session) async {
    if (rotateReject) throw const AuthFailure('revoked', status: 401);
    return initial;
  }
}

void main() {
  const owner = '11111111-1111-4111-8111-111111111111',
      device = '22222222-2222-4222-8222-222222222222';
  final server = Uri.parse('https://example.invalid');
  AuthSession session() => AuthSession(
    userId: owner,
    deviceId: device,
    accessToken: 'sr_a_${'a' * 43}',
    refreshToken: 'sr_r_${'r' * 43}',
    accessExpiresAt: DateTime.utc(2099),
    refreshExpiresAt: DateTime.utc(2099),
  );
  test('device proof is same-origin header-only and never receives normal login credentials', () async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => http.close(force: true));
    var mode = 'confirmed';
    http.listen((request) async {
      expect(request.uri.path, '/v1/account/deletion-device-confirmations');
      expect(request.uri.hasQuery, isFalse);
      expect(request.method, 'POST');
      expect(request.headers.value('Authorization'), isNull);
      expect(
        request.headers.value('X-Deletion-Device-Proof'),
        session().refreshToken,
      );
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body, {'user_id': owner, 'device_id': device});
      request.response.headers.contentType = ContentType.json;
      if (mode == 'unknown') request.response.statusCode = 404;
      request.response.write(
        jsonEncode(
          mode == 'invalid'
              ? {'deletion_confirmed': true, 'owner_id': owner}
              : {'deletion_confirmed': true},
        ),
      );
      await request.response.close();
    });
    final api = HttpAuthApi(
      Uri.parse('http://127.0.0.1:${http.port}'),
      allowLocalHttp: true,
    );
    expect((await api.confirmDeletion(session()))?.userId, owner);
    mode = 'unknown';
    expect(await api.confirmDeletion(session()), isNull);
    mode = 'invalid';
    expect(await api.confirmDeletion(session()), isNull);
  });
  test('reconnection confirms deleted owner before server use and unknown response preserves data', () async {
    final vault = Vault()..value = jsonEncode(session().toJson()),
        api = Aware(session());
    var opened = 0, deleted = 0;
    final controller = AuthController(
      api: api,
      vault: vault,
      proofs: Social(),
      openAccount: (_) async {
        opened++;
      },
      closeAccount: () async {},
      deleteAccountFiles: (proof) async {
        expect(proof.userId, owner);
        deleted++;
      },
    );
    api.result = AccountDeletionConfirmation.device(owner, server, {
      'deletion_confirmed': true,
    });
    await controller.restore();
    await expectLater(controller.validSession(), throwsA(isA<AuthFailure>()));
    expect(controller.phase, AuthPhase.signedOut);
    expect(opened, 1);
    expect(deleted, 1);
    expect(controller.session, isNull);
    controller.dispose();
    final retained = Vault()..value = jsonEncode(session().toJson());
    api.result = null;
    final second = AuthController(
      api: api,
      vault: retained,
      proofs: Social(),
      openAccount: (_) async {
        opened++;
      },
      closeAccount: () async {},
      deleteAccountFiles: (_) async {
        deleted++;
      },
    );
    await second.restore();
    expect(second.phase, AuthPhase.ready);
    expect(deleted, 1);
    expect(opened, 2);
    second.dispose();
  });
  test(
    'status proof for old A removes only A without signing out current B',
    () async {
      final b = AuthSession(
        userId: device,
        deviceId: owner,
        accessToken: 'synthetic',
        refreshToken: 'synthetic',
        accessExpiresAt: DateTime.utc(2099),
        refreshExpiresAt: DateTime.utc(2099),
      );
      var closed = 0;
      final removed = <String>[];
      final api = Aware(b), vault = Vault()..value = jsonEncode(b.toJson());
      final controller = AuthController(
        api: api,
        vault: vault,
        proofs: Social(),
        openAccount: (_) async {},
        closeAccount: () async {
          closed++;
        },
        deleteAccountFiles: (proof) async {
          removed.add(proof.userId);
        },
      );
      await controller.restore();
      await controller.applyConfirmedDeletion(
        AccountDeletionConfirmation.receipt(owner, server, 'ACCEPTED'),
      );
      expect(controller.session?.userId, device);
      expect(controller.phase, AuthPhase.ready);
      expect(closed, 0);
      expect(removed, [owner]);
      controller.dispose();
    },
  );
}
