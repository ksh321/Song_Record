import 'auth_session.dart';

class LinkChallenge {
  const LinkChallenge(this.id, this.nonce);
  factory LinkChallenge.fromJson(Map<String, dynamic> json) =>
      LinkChallenge(json['challengeId'] as String, json['nonce'] as String);
  final String id, nonce;
  @override
  String toString() => 'LinkChallenge[REDACTED]';
}

abstract interface class IdentityLinkApi {
  Future<List<String>> identities(AuthSession session);
  Future<LinkChallenge> beginLink(
    AuthSession session,
    String provider,
    String target,
  );
  Future<LinkChallenge> reauthenticate(
    AuthSession session,
    String id,
    String proof,
  );
  Future<void> finishLink(AuthSession session, String id, String proof);
}

abstract interface class IdentityLinkProofSource {
  Future<String> linkProof(String provider, String nonce);
}

/// Linking only adds a login method. It never opens another user's local store.
class IdentityLinkFlow {
  IdentityLinkFlow(this.auth, this.api, this.proofs);
  final AuthController auth;
  final IdentityLinkApi api;
  final IdentityLinkProofSource proofs;
  bool _busy = false;
  Future<List<String>> load() async =>
      api.identities(await auth.validSession());
  Future<void> link(String existing, String target) async {
    if (_busy) throw const AuthFailure('계정 연결을 진행 중이에요.');
    _busy = true;
    try {
      final original = await auth.validSession();
      Future<AuthSession> current() async {
        final next = await auth.validSession();
        if (next.userId != original.userId ||
            next.deviceId != original.deviceId) {
          throw const AuthFailure('로그인 계정이 변경됐어요. 처음부터 다시 시도해 주세요.');
        }
        return next;
      }

      final reauth = await api.beginLink(original, existing, target);
      final firstProof = await proofs.linkProof(existing, reauth.nonce);
      final challenge = await api.reauthenticate(
        await current(),
        reauth.id,
        firstProof,
      );
      final secondProof = await proofs.linkProof(target, challenge.nonce);
      await api.finishLink(await current(), challenge.id, secondProof);
    } finally {
      _busy = false;
    }
  }
}
