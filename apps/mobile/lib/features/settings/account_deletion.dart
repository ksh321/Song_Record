import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/domain/identifiers.dart';

import '../auth/auth_session.dart';
import '../auth/identity_link.dart';

class DeletionReceipt {
  DeletionReceipt(
    this.scope,
    this.preparation,
    this.token,
    this.proof,
    this.revision,
    this.expires,
    this.operation,
  );
  final String scope, preparation, token, proof, operation;
  final int revision;
  final DateTime expires;
  Map<String, Object?> get command => {
    'preparation_id': preparation,
    'base_revision': revision,
    'reauth_proof': proof,
    'scope': 'ALL_ACCOUNT_DATA',
    'confirmed': true,
  };
  Map<String, Object?> toJson() => {
    'version': 1,
    'scope': scope,
    'preparation': preparation,
    'token': token,
    'proof': proof,
    'revision': revision,
    'expires': expires.toIso8601String(),
    'operation': operation,
  };
  @override
  String toString() => 'DeletionReceipt[REDACTED]';
  static DeletionReceipt decode(String value, String scope) {
    final m = jsonDecode(value);
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    if (m is! Map ||
        m['version'] != 1 ||
        m['scope'] != scope ||
        !uuid.hasMatch(m['preparation'] as String? ?? '') ||
        !uuid.hasMatch(m['proof'] as String? ?? '') ||
        !uuid.hasMatch(m['operation'] as String? ?? '') ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(m['token'] as String? ?? '') ||
        m['revision'] is! int ||
        (m['revision'] as int) < 1) {
      throw const FormatException('Invalid protected deletion receipt');
    }
    return DeletionReceipt(
      scope,
      m['preparation'] as String,
      m['token'] as String,
      m['proof'] as String,
      m['revision'] as int,
      DateTime.parse(m['expires'] as String),
      m['operation'] as String,
    );
  }
}

abstract interface class DeletionReceiptVault {
  Future<String?> read(String scope);
  Future<void> write(String scope, String value);
}

class SecureDeletionReceiptVault implements DeletionReceiptVault {
  const SecureDeletionReceiptVault();
  static const storage = FlutterSecureStorage();
  static Future<void> _writes = Future<void>.value();
  String key(String scope) =>
      'account_deletion_receipt_${sha256.convert(utf8.encode(scope))}';
  @override
  Future<String?> read(String scope) => storage.read(key: key(scope));
  @override
  Future<void> write(String scope, String value) {
    final operation = _writes.then((_) async {
      final raw = await storage.read(key: 'account_deletion_receipt_index');
      final decoded = raw == null ? <dynamic>[] : jsonDecode(raw);
      if (decoded is! List || decoded.any((s) => s is! String)) {
        throw const FormatException('Invalid protected confirmation index');
      }
      final scopes = decoded.cast<String>().toSet()..add(scope);
      await storage.write(key: key(scope), value: value);
      await storage.write(
        key: 'account_deletion_receipt_index',
        value: jsonEncode(scopes.toList()),
      );
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  static Future<List<String>> scopes(String prefix) async {
    await _writes;
    final raw = await storage.read(key: 'account_deletion_receipt_index');
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((s) => s is! String)) {
      throw const FormatException('Invalid protected confirmation index');
    }
    return decoded.cast<String>().where((s) => s.startsWith(prefix)).toList();
  }
}

/// Fixed same-origin endpoints only. The status proof never appears in a URL or log.
class AccountDeletionApi {
  AccountDeletionApi(
    this.base,
    this.session,
    this.guard, {
    this.local = false,
  }) {
    if (base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.scheme != 'https' &&
            !(local &&
                base.scheme == 'http' &&
                {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(base.host))) {
      throw ArgumentError('Invalid deletion origin');
    }
  }
  final Uri base;
  final Future<AuthSession> Function() session;
  final void Function() guard;
  final bool local;
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, Object?>? body,
    String? operation,
    String? statusToken,
    bool statusOnly = false,
  }) async {
    const uuid =
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
    if (statusOnly
        ? !RegExp('^/v1/account/deletion-status/$uuid\$').hasMatch(path)
        : !{
            '/v1/account/deletion-reauth-challenges',
            '/v1/account/deletion-status-preparations',
            '/v1/account/deletion-requests',
          }.contains(path)) {
      throw ArgumentError('Invalid deletion route');
    }
    AuthSession? auth;
    if (!statusOnly) {
      guard();
      auth = await session();
      guard();
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final req = await client.openUrl(
          statusOnly ? 'GET' : 'POST',
          base.resolve(path),
        );
        req.followRedirects = false;
        req.headers.set('Cache-Control', 'no-store');
        if (!statusOnly) {
          guard();
          req.headers.set('Authorization', 'Bearer ${auth!.accessToken}');
          req.headers.set('X-Device-Id', auth.deviceId);
        }
        if (statusToken != null) {
          req.headers.set('X-Deletion-Status-Token', statusToken);
        }
        if (operation != null) {
          req.headers.set('Idempotency-Key', operation);
        }
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final res = await req.close();
        final bytes = <int>[];
        await for (final c in res) {
          if (bytes.length + c.length > 65536) {
            throw const FormatException('Deletion response too large');
          }
          bytes.addAll(c);
        }
        if (!statusOnly) {
          guard();
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw DeletionFailure(res.statusCode);
        }
        final result = jsonDecode(utf8.decode(bytes));
        if (result is! Map<String, dynamic>) {
          throw const FormatException('Invalid deletion response');
        }
        return result;
      })().timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }
}

class DeletionFailure implements Exception {
  const DeletionFailure(this.status);
  final int status;
  @override
  String toString() => '탈퇴 요청을 확인하지 못했어요. 확인증으로 접수 상태를 확인해 주세요.';
}

class AccountDeletionFlow {
  AccountDeletionFlow(this.scope, this.api, this.proofs, this.vault);
  final String scope;
  final AccountDeletionApi api;
  final IdentityLinkProofSource proofs;
  final DeletionReceiptVault vault;
  DeletionReceipt? receipt;
  bool busy = false;
  bool loaded = false;
  Future<void> restore() async {
    loaded = false;
    final raw = await vault.read(scope);
    if (raw != null) {
      receipt = DeletionReceipt.decode(raw, scope);
    }
    loaded = true;
  }

  Future<void> prepare(String provider) async {
    if (!loaded || busy) {
      throw StateError('An existing protected request must be checked first');
    }
    busy = true;
    try {
      if (receipt != null) {
        try {
          await status();
          throw StateError('Existing protected confirmation is still valid');
        } on DeletionFailure catch (error) {
          if (error.status != 410) rethrow;
          // Only server-confirmed expiry and a fresh ACTIVE-owner challenge allow replacement.
        }
      }
      api.guard();
      final c = await api.call(
        '/v1/account/deletion-reauth-challenges',
        body: {'provider': provider},
      );
      final proof = await proofs.linkProof(provider, c['nonce'] as String);
      api.guard();
      final p = await api.call(
        '/v1/account/deletion-status-preparations',
        body: {'challenge_id': c['challenge_id'], 'proof': proof},
      );
      final r = DeletionReceipt.decode(
        jsonEncode({
          'version': 1,
          'scope': scope,
          'preparation': p['preparation_id'],
          'token': p['status_token'],
          'proof': p['reauth_proof'],
          'revision': p['base_revision'],
          'expires': p['prepare_expires_at'],
          'operation': UuidValue.random().value,
        }),
        scope,
      );
      api.guard();
      await vault.write(scope, jsonEncode(r.toJson()));
      api.guard();
      final saved = await vault.read(scope);
      api.guard();
      if (saved == null || saved != jsonEncode(r.toJson())) {
        throw StateError('Protected confirmation could not be verified');
      }
      receipt = r;
    } finally {
      busy = false;
    }
  }

  Future<Map<String, dynamic>> status() async {
    final r = receipt;
    if (r == null) {
      throw StateError('No protected confirmation');
    }
    final result = await api.call(
      '/v1/account/deletion-status/${r.preparation}',
      statusOnly: true,
      statusToken: r.token,
    );
    if (!{
          'PREPARED',
          'ACCEPTED',
          'DELETING',
          'BACKUP_CLEANUP',
          'COMPLETED',
        }.contains(result['status']) ||
        result.keys.any(
          (k) => !{
            'status',
            'accepted_at',
            'service_deleted_at',
            'backup_purge_due_at',
            'completed_at',
            'expires_at',
            'retrying',
          }.contains(k),
        ) ||
        result['retrying'] is! bool) {
      throw const FormatException('Invalid restricted status');
    }
    return result;
  }

  Future<Map<String, dynamic>> accept({required bool confirmed}) async {
    if (!confirmed || receipt == null || busy) {
      throw StateError('Explicit confirmation and protected receipt required');
    }
    busy = true;
    try {
      final r = receipt!;
      api.guard();
      try {
        await api.call(
          '/v1/account/deletion-requests',
          body: r.command,
          operation: r.operation,
          statusToken: r.token,
        );
      } catch (_) {
        /* The server may have accepted before the reply was lost. The protected proof resolves it. */
      }
      return await status();
    } finally {
      busy = false;
    }
  }
}
