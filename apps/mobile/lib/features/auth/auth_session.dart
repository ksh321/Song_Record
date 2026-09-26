import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'account_actions.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.status = 0});
  final String message;
  final int status;
  @override
  String toString() => message;
}

class LoginCancelled implements Exception {}

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.deviceId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });
  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    userId: json['userId'] as String,
    deviceId: json['deviceId'] as String,
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    accessExpiresAt: DateTime.parse(json['accessExpiresAt'] as String).toUtc(),
    refreshExpiresAt: DateTime.parse(json['refreshExpiresAt'] as String)
        .toUtc(),
  );
  final String userId, deviceId, accessToken, refreshToken;
  final DateTime accessExpiresAt, refreshExpiresAt;
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'deviceId': deviceId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'accessExpiresAt': accessExpiresAt.toIso8601String(),
    'refreshExpiresAt': refreshExpiresAt.toIso8601String(),
  };
  @override
  String toString() => 'AuthSession[REDACTED]';
}

abstract interface class SessionVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

abstract interface class AuthApi {
  Future<AuthSession> login(String provider, String proof);
  Future<AuthSession> refresh(AuthSession session);
  Future<String> me(AuthSession session);
}

abstract interface class SocialProofSource {
  Future<String> proof(String provider);
}

enum AuthPhase { loading, signedOut, ready, unavailable }

/// One instance per app. Secure persistence finishes before a new token becomes usable.
class AuthController extends ChangeNotifier {
  AuthController({
    required this.api,
    required this.vault,
    required this.proofs,
    required this.openAccount,
    required this.closeAccount,
    this.prepareLogout,
    this.exportRecovery,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final AuthApi api;
  final SessionVault vault;
  final SocialProofSource proofs;
  final Future<void> Function(String) openAccount;
  final Future<void> Function() closeAccount;
  final DateTime Function() now;
  final Future<void> Function()? prepareLogout;
  final Future<bool> Function()? exportRecovery;
  bool _loggingOut = false;
  AuthSession? session;
  AuthPhase phase = AuthPhase.loading;
  String? message;
  bool busy = false;
  Future<AuthSession>? _refreshing;

  Future<void> restore() async {
    if (busy) {
      return;
    }
    busy = true;
    phase = AuthPhase.loading;
    message = null;
    notifyListeners();
    try {
      final raw = await vault.read();
      if (raw == null) {
        phase = AuthPhase.signedOut;
        return;
      }
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      if (saved['signedOut'] == true) {
        await vault.clear();
        phase = AuthPhase.signedOut;
        return;
      }
      if (saved['refreshPending'] == true) {
        await _requireLogin('로그인 갱신이 중단됐어요. 다시 로그인해 주세요.');
        return;
      }
      session = AuthSession.fromJson(saved);
      final current = await validSession();
      final user = await api.me(current);
      if (user != current.userId) {
        throw const AuthFailure('계정을 다시 확인해 주세요.', status: 401);
      }
      await openAccount(user);
      phase = AuthPhase.ready;
    } on AuthFailure catch (e) {
      if (e.status == 401) {
        await _requireLogin(e.message);
      } else {
        phase = AuthPhase.unavailable;
        message = e.message;
      }
    } catch (_) {
      phase = AuthPhase.unavailable;
      message = '로그인 정보를 열지 못했어요. 다시 시도해 주세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String provider) async {
    if (busy) {
      return;
    }
    busy = true;
    message = null;
    notifyListeners();
    try {
      final proof = await proofs.proof(provider);
      final next = await api.login(provider, proof);
      await closeAccount();
      await vault.write(jsonEncode(next.toJson()));
      session = next;
      await openAccount(next.userId);
      phase = AuthPhase.ready;
    } on LoginCancelled {
      message = '로그인을 취소했어요.';
    } on AuthFailure catch (e) {
      message = e.message;
    } catch (_) {
      message = '로그인하지 못했어요. 잠시 후 다시 시도해 주세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (busy) throw const AuthFailure('진행 중인 작업이 끝난 뒤 다시 시도해 주세요.');
    if (api is! AccountActionsApi) {
      throw const AuthFailure('로그아웃을 지원하지 않는 실행 모드예요.');
    }
    busy = true;
    _loggingOut = true;
    notifyListeners();
    try {
      await prepareLogout?.call();
      final rotating = _refreshing;
      if (rotating != null) {
        try {
          await rotating;
        } on AuthFailure {
          /* Login was already invalidated. */
        }
      }
      final current = session;
      if (current != null) {
        // Do not claim server logout when the network request failed.
        await (api as AccountActionsApi).logout(current);
      }
      await vault.write(jsonEncode({'signedOut': true}));
      await closeAccount();
      session = null;
      phase = AuthPhase.signedOut;
      message = '로그아웃했어요. 이 기기의 기록은 원래 계정에 보관돼요.';
      try {
        await vault.clear();
      } catch (_) {
        /* Persistent tombstone prevents restore. */
      }
    } finally {
      _loggingOut = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<AuthSession> validSession() async {
    if (_loggingOut) throw const AuthFailure('로그아웃 중이에요.');
    final current = session;
    if (current == null) {
      throw const AuthFailure('다시 로그인해 주세요.', status: 401);
    }
    if (!current.refreshExpiresAt.isAfter(now().toUtc())) {
      await _requireLogin('로그인이 만료됐어요. 다시 로그인해 주세요.');
      throw const AuthFailure('다시 로그인해 주세요.', status: 401);
    }
    if (current.accessExpiresAt.isAfter(
      now().toUtc().add(const Duration(seconds: 30)),
    )) {
      return current;
    }
    return _refreshing ??= _rotate(current)
        .whenComplete(() => _refreshing = null);
  }

  Future<AuthSession> _rotate(AuthSession current) async {
    try {
      // A crash or lost refresh response must not replay the old refresh token on restart.
      await vault.write(
        jsonEncode({...current.toJson(), 'refreshPending': true}),
      );
      final next = await api.refresh(current);
      if (next.userId != current.userId || next.deviceId != current.deviceId) {
        throw const AuthFailure('계정 확인이 필요해요.', status: 401);
      }
      await vault.write(jsonEncode(next.toJson()));
      session = next;
      return next;
    } catch (_) {
      await _requireLogin('로그인 갱신을 확인하지 못했어요. 다시 로그인해 주세요.');
      throw const AuthFailure('다시 로그인해 주세요.', status: 401);
    }
  }

  Future<void> _requireLogin(String text) async {
    session = null;
    phase = AuthPhase.signedOut;
    message = text;
    await closeAccount(); // closes handles only; local files and queued edits remain.
    await vault.clear();
    notifyListeners();
  }
}
