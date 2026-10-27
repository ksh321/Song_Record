import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/domain/account_deletion_confirmation.dart';
import 'account_actions.dart';

class AuthFailure implements Exception {
  const AuthFailure(
    this.message, {
    this.status = 0,
    this.requestNotSent = false,
  });
  final String message;
  final int status;

  /// True only when transport proves that no request could reach the server.
  final bool requestNotSent;
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

abstract interface class DeletionAwareAuthApi {
  Future<AccountDeletionConfirmation?> confirmDeletion(AuthSession session);
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
    this.deleteAccountFiles,
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
  final Future<void> Function(AccountDeletionConfirmation)? deleteAccountFiles;
  final Map<String, DateTime> _deletionProbeTimes = {};
  final Future<bool> Function()? exportRecovery;
  bool _loggingOut = false;
  final Set<String> _acceptedDeletionOwners = {};
  AuthSession? session;
  AuthPhase phase = AuthPhase.loading;
  String? message;
  bool busy = false;
  Future<AuthSession>? _refreshing;
  Future<AuthSession>? _validating;
  bool serverLoginRequired = false;
  bool networkAvailable = true;
  bool _ownerVerified = false;

  void setNetworkAvailable(bool value) {
    if (networkAvailable == value) return;
    networkAvailable = value;
    notifyListeners();
  }

  int _accountEpoch = 0;
  String? _accountTag;
  int get accountEpoch => _accountEpoch;
  @override
  void notifyListeners() {
    final tag = '$phase:${session?.userId}:${session?.deviceId}';
    if (tag != _accountTag) {
      _accountTag = tag;
      _accountEpoch++;
    }
    super.notifyListeners();
  }

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
      session = AuthSession.fromJson(saved);
      serverLoginRequired =
          saved['refreshPending'] == true ||
          saved['serverLoginRequired'] == true ||
          !session!.refreshExpiresAt.isAfter(now().toUtc());
      _ownerVerified = false;
      // Secure, environment-scoped local identity opens only its own store.
      // Online authentication is a separate prerequisite for any server request.
      await openAccount(session!.userId);
      phase = AuthPhase.ready;
      if (serverLoginRequired) {
        message = '서버 동기화를 위해 다시 로그인해 주세요. 기기의 기록은 계속 사용할 수 있어요.';
      }
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

  Future<void> signIn(String provider) => _signIn(provider, false);

  Future<void> reauthenticate(String provider) => _signIn(provider, true);

  Future<void> _signIn(String provider, bool sameAccountOnly) async {
    if (busy) {
      return;
    }
    busy = true;
    message = null;
    notifyListeners();
    try {
      final validating = _validating;
      if (validating != null) {
        try {
          await validating;
        } catch (_) {
          /* Online renewal may be unavailable. */
        }
      }
      final proof = await proofs.proof(provider);
      final next = await api.login(provider, proof);
      final local = sameAccountOnly && phase == AuthPhase.ready
          ? session
          : null;
      if (sameAccountOnly && local == null) {
        throw const AuthFailure('열린 계정이 없어요. 로그인 화면에서 다시 시작해 주세요.');
      }
      if (_acceptedDeletionOwners.contains(next.userId)) {
        throw const AuthFailure('탈퇴가 확인된 계정은 다시 열 수 없어요.');
      }
      if (local != null && local.userId != next.userId) {
        throw const AuthFailure(
          '이 기기에 열린 기록과 같은 계정으로 로그인해 주세요. 다른 계정은 로그아웃 후 사용할 수 있어요.',
        );
      }
      if (local == null) await closeAccount();
      await vault.write(jsonEncode(next.toJson()));
      session = next;
      serverLoginRequired = false;
      _ownerVerified = true;
      if (local == null) await openAccount(next.userId);
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
      final rotating = _validating ?? _refreshing;
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

  /// Called only after the dedicated deletion proof confirms acceptance for this owner.
  /// Closes account handles; physical per-account file cleanup belongs to verified deletion sync.
  Future<void> deletionAccepted(
    String owner, {
    AccountDeletionConfirmation? confirmation,
  }) => _applyDeletion(owner, confirmation, true);
  Future<void> applyConfirmedDeletion(
    AccountDeletionConfirmation confirmation,
  ) => _applyDeletion(confirmation.userId, confirmation, true);
  Future<void> _applyDeletion(
    String owner,
    AccountDeletionConfirmation? confirmation,
    bool joinRotation,
  ) async {
    if (confirmation != null && confirmation.userId != owner) {
      throw StateError('Deletion confirmation owner mismatch');
    }
    _acceptedDeletionOwners.add(owner);
    if (session?.userId != owner) {
      if (confirmation != null) await deleteAccountFiles?.call(confirmation);
      return;
    }
    _acceptedDeletionOwners.add(owner);
    _loggingOut = true;
    busy = true;
    session = null;
    phase = AuthPhase.signedOut;
    message = '계정 탈퇴가 접수됐어요. 저장된 확인증으로 삭제 상태를 확인할 수 있어요.';
    notifyListeners();
    try {
      final rotating = _refreshing;
      if (joinRotation && rotating != null) {
        try {
          await rotating;
        } catch (_) {
          /* Server acceptance already revoked this owner. */
        }
      }
      await vault.write(jsonEncode({'signedOut': true}));
    } finally {
      try {
        await closeAccount();
        if (confirmation != null) await deleteAccountFiles?.call(confirmation);
      } finally {
        _loggingOut = false;
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<AuthSession> validSession() =>
      _validating ??= _validateSession().whenComplete(() => _validating = null);

  Future<AuthSession> _validateSession() async {
    if (_loggingOut) throw const AuthFailure('로그아웃 중이에요.');
    if (busy) throw const AuthFailure('로그인 처리가 끝난 뒤 다시 시도해 주세요.');
    final current = session;
    if (current == null) {
      throw const AuthFailure('다시 로그인해 주세요.', status: 401);
    }
    if (!networkAvailable) {
      throw const AuthFailure(
        '오프라인이에요. 기기에 저장하고 연결되면 동기화해요.',
        requestNotSent: true,
      );
    }
    if (_refreshing == null && api is DeletionAwareAuthApi) {
      final last = _deletionProbeTimes[current.userId];
      if (last == null ||
          now().toUtc().difference(last) >= const Duration(minutes: 1)) {
        _deletionProbeTimes[current.userId] = now().toUtc();
        final confirmation = await (api as DeletionAwareAuthApi)
            .confirmDeletion(current);
        if (confirmation != null) {
          if (confirmation.userId != current.userId) {
            throw const AuthFailure('계정 삭제 확인의 소유자가 다릅니다.');
          }
          await applyConfirmedDeletion(confirmation);
          throw const AuthFailure('계정 탈퇴가 확인됐어요.', status: 401);
        }
        if (!identical(session, current)) {
          throw const AuthFailure('계정이 바뀌었어요.', status: 401);
        }
      }
    }
    if (serverLoginRequired ||
        !current.refreshExpiresAt.isAfter(now().toUtc())) {
      await _requireServerLogin(current);
      throw const AuthFailure('다시 로그인해 주세요.', status: 401);
    }
    final usable =
        current.accessExpiresAt.isAfter(
          now().toUtc().add(const Duration(seconds: 30)),
        )
        ? current
        : await (_refreshing ??= _rotate(current)
              .whenComplete(() => _refreshing = null));
    if (!_ownerVerified) {
      try {
        final owner = await api.me(usable);
        if (!identical(session, usable) || _loggingOut) {
          throw const AuthFailure('계정이 바뀌었어요.', status: 401);
        }
        if (owner != usable.userId) {
          await _requireLogin('계정을 다시 확인해 주세요.');
          throw const AuthFailure('계정이 일치하지 않아요.', status: 401);
        }
        _ownerVerified = true;
      } on AuthFailure catch (error) {
        if (error.status == 401 && identical(session, usable)) {
          await _requireServerLogin(usable);
        }
        rethrow;
      }
    }
    if (!identical(session, usable) || _loggingOut) {
      throw const AuthFailure('계정이 바뀌었어요.', status: 401);
    }
    return usable;
  }

  Future<void> _requireServerLogin(AuthSession current) async {
    if (!identical(session, current) ||
        _acceptedDeletionOwners.contains(current.userId)) {
      return;
    }
    serverLoginRequired = true;
    message = '서버 동기화를 위해 다시 로그인해 주세요. 기기의 기록은 계속 사용할 수 있어요.';
    notifyListeners();
    await vault.write(
      jsonEncode({...current.toJson(), 'serverLoginRequired': true}),
    );
    if (_acceptedDeletionOwners.contains(current.userId)) {
      await vault.write(jsonEncode({'signedOut': true}));
    }
  }

  Future<AuthSession> _rotate(AuthSession current) async {
    try {
      // A crash or lost refresh response must not replay the old refresh token on restart.
      await vault.write(
        jsonEncode({...current.toJson(), 'refreshPending': true}),
      );
      final next = await api.refresh(current);
      if (_acceptedDeletionOwners.contains(current.userId)) {
        throw const AuthFailure('계정 탈퇴가 접수됐어요.', status: 401);
      }
      if (next.userId != current.userId || next.deviceId != current.deviceId) {
        await _requireLogin('계정 확인이 필요해요.');
        throw const AuthFailure('계정 확인이 필요해요.', status: 401);
      }
      if (!identical(session, current)) {
        throw const AuthFailure('계정이 바뀌었어요.', status: 401);
      }
      await vault.write(jsonEncode(next.toJson()));
      if (_acceptedDeletionOwners.contains(current.userId)) {
        await vault.write(jsonEncode({'signedOut': true}));
        throw const AuthFailure('계정 탈퇴가 접수됐어요.', status: 401);
      }
      session = next;
      return next;
    } catch (error) {
      if (_acceptedDeletionOwners.contains(current.userId)) {
        throw const AuthFailure('계정 탈퇴가 접수됐어요.', status: 401);
      }
      if (error is AuthFailure &&
          error.status == 401 &&
          api is DeletionAwareAuthApi) {
        final confirmation = await (api as DeletionAwareAuthApi)
            .confirmDeletion(current);
        if (confirmation != null) {
          await _applyDeletion(current.userId, confirmation, false);
          throw const AuthFailure('계정 탈퇴가 확인됐어요.', status: 401);
        }
      }
      if (identical(session, current) &&
          error is AuthFailure &&
          error.requestNotSent) {
        await vault.write(jsonEncode(current.toJson()));
        rethrow;
      }
      await _requireServerLogin(current);
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
