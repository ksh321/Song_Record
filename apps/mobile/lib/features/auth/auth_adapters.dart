import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

import 'auth_session.dart';
import 'identity_link.dart';

class SecureSessionVault implements SessionVault {
  SecureSessionVault(String scope)
    : key = 'session_${sha256.convert(utf8.encode(scope))}';
  final String key;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}

class HttpAuthApi implements AuthApi, IdentityLinkApi {
  HttpAuthApi(this.base, {this.allowLocalHttp = false}) {
    if (base.scheme != 'https' &&
        !(allowLocalHttp &&
            base.scheme == 'http' &&
            {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(base.host))) {
      throw ArgumentError(
        'Authentication requires HTTPS or a local development tunnel',
      );
    }
    if (base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment) {
      throw ArgumentError('Invalid API address');
    }
  }
  final Uri base;
  final bool allowLocalHttp;
  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
    AuthSession? session,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        final request = await client.openUrl(
          body == null ? 'GET' : 'POST',
          base.resolve(path),
        );
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (session != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${session.accessToken}',
          );
          request.headers.set('X-Device-Id', session.deviceId);
        }
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 65536) {
            throw const AuthFailure('서버 응답을 확인하지 못했어요.');
          }
          bytes.addAll(chunk);
        }
        if (response.statusCode != 200) {
          String? code;
          try {
            final decoded = jsonDecode(utf8.decode(bytes));
            final error = decoded is Map ? decoded['error'] : null;
            if (error is Map && error['code'] is String) {
              code = error['code'] as String;
            }
          } on FormatException {
            // Preserve HTTP status even when a proxy returns a non-JSON error.
          }
          const linkErrors = {
            'IDENTITY_IN_USE': '다른 노래기록 계정에서 사용 중이에요. 계정은 자동으로 합쳐지지 않아요.',
            'IDENTITY_ALREADY_LINKED': '이미 연결된 로그인 수단이에요. 새로고침해 주세요.',
            'REAUTH_IDENTITY_MISMATCH': '현재 계정에 연결된 계정으로 다시 인증해 주세요.',
            'LINK_CHALLENGE_EXPIRED': '연결 요청이 만료됐거나 사용됐어요. 처음부터 다시 시도해 주세요.',
            'AUTH_INVALID_PROOF': '인증 정보를 확인하지 못했어요. 처음부터 다시 시도해 주세요.',
          };
          throw AuthFailure(
            linkErrors[code] ??
                (response.statusCode == 401
                    ? '다시 로그인해 주세요.'
                    : '로그인 서버 요청에 실패했어요. 잠시 후 다시 시도해 주세요.'),
            status: response.statusCode,
          );
        }
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      })().timeout(const Duration(seconds: 20));
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<String>> identities(AuthSession session) async {
    final data = await _request('/v1/auth/identities', session: session);
    return (data['identities'] as List)
        .map((item) => (item as Map)['provider'] as String)
        .toSet()
        .toList();
  }

  @override
  Future<LinkChallenge> beginLink(
    AuthSession session,
    String provider,
    String target,
  ) async => LinkChallenge.fromJson(
    await _request(
      '/v1/auth/identities/reauth-challenges',
      session: session,
      body: {'provider': provider, 'targetProvider': target},
    ),
  );
  @override
  Future<LinkChallenge> reauthenticate(
    AuthSession session,
    String id,
    String proof,
  ) async => LinkChallenge.fromJson(
    await _request(
      '/v1/auth/identities/link-challenges',
      session: session,
      body: {'challengeId': id, 'proof': proof},
    ),
  );
  @override
  Future<void> finishLink(AuthSession session, String id, String proof) async {
    await _request(
      '/v1/auth/identities/link',
      session: session,
      body: {'challengeId': id, 'proof': proof},
    );
  }

  @override
  Future<AuthSession> login(String provider, String proof) async =>
      AuthSession.fromJson(
        await _request(
          '/v1/auth/social',
          body: {'provider': provider, 'proof': proof, 'deviceName': 'Android'},
        ),
      );
  @override
  Future<AuthSession> refresh(AuthSession session) async =>
      AuthSession.fromJson(
        await _request(
          '/v1/auth/refresh',
          body: {
            'refreshToken': session.refreshToken,
            'deviceId': session.deviceId,
          },
        ),
      );
  @override
  Future<String> me(AuthSession session) async =>
      (await _request('/v1/auth/me', session: session))['userId'] as String;
}

class SdkSocialProofSource
    implements SocialProofSource, IdentityLinkProofSource {
  SdkSocialProofSource({required this.googleClientId, required this.kakaoKey});
  final String googleClientId, kakaoKey;
  Future<void>? _kakaoInitialization;
  final _kakaoTokens = _MemoryKakaoTokens();
  Future<void> _initializeKakao() async {
    await kakao.KakaoSdk.init(nativeAppKey: kakaoKey, loggingEnabled: false);
    kakao.TokenManagerProvider.instance.manager = _kakaoTokens;
  }

  bool _isKakaoCancellation(Object error) =>
      error is PlatformException && error.code == 'CANCELED' ||
      error is kakao.KakaoClientException &&
          error.reason == kakao.ClientErrorCause.cancelled ||
      error is kakao.KakaoAuthException &&
          error.error == kakao.AuthErrorCause.accessDenied;
  @override
  Future<String> linkProof(String provider, String nonce) async {
    try {
      if (provider == 'GOOGLE') {
        final token = await const MethodChannel('song_record/identity_link')
            .invokeMethod<String>('googleProof', {
              'clientId': googleClientId,
              'nonce': nonce,
            });
        if (token == null) throw const AuthFailure('Google 인증 정보를 받지 못했어요.');
        return token;
      }
      if (provider != 'KAKAO') throw const AuthFailure('지원하지 않는 로그인 방식이에요.');
      await (_kakaoInitialization ??= _initializeKakao());
      final token = await kakao.UserApi.instance.loginWithKakaoAccount(
        nonce: nonce,
        prompts: [kakao.Prompt.login],
      );
      if (token.idToken == null) {
        throw const AuthFailure('카카오 OpenID Connect 설정을 확인해 주세요.');
      }
      return token.idToken!;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      if (_isKakaoCancellation(e) ||
          e is PlatformException && e.code == 'CANCELED') {
        throw LoginCancelled();
      }
      throw const AuthFailure('계정 인증에 실패했어요. 처음부터 다시 시도해 주세요.');
    } finally {
      await _kakaoTokens.clear();
    }
  }

  static Future<void>? _googleInitialization;
  @override
  Future<String> proof(String provider) async {
    if (provider == 'GOOGLE') {
      try {
        await (_googleInitialization ??= GoogleSignIn.instance.initialize(
          serverClientId: googleClientId,
        ));
        final account = await GoogleSignIn.instance.authenticate();
        final token = account.authentication.idToken;
        if (token == null) {
          throw const AuthFailure('Google 로그인 정보를 받지 못했어요.');
        }
        return token;
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) {
          throw LoginCancelled();
        }
        throw const AuthFailure('Google 로그인에 실패했어요. 다시 시도해 주세요.');
      }
    }
    if (provider != 'KAKAO') {
      throw const AuthFailure('지원하지 않는 로그인 방식이에요.');
    }
    try {
      await (_kakaoInitialization ??= _initializeKakao());
      kakao.OAuthToken token;
      if (await kakao.isKakaoTalkInstalled()) {
        try {
          token = await kakao.UserApi.instance.loginWithKakaoTalk();
        } catch (e) {
          if (_isKakaoCancellation(e)) {
            throw LoginCancelled();
          }
          token = await kakao.UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        token = await kakao.UserApi.instance.loginWithKakaoAccount();
      }
      return token.accessToken;
    } on LoginCancelled {
      rethrow;
    } catch (e) {
      if (_isKakaoCancellation(e)) {
        throw LoginCancelled();
      }
      throw const AuthFailure('카카오 로그인에 실패했어요. 다시 시도해 주세요.');
    } finally {
      await _kakaoTokens.clear();
    }
  }
}

// Provider credentials are only needed during the server proof exchange.
class _MemoryKakaoTokens implements kakao.TokenManager {
  kakao.OAuthToken? _token;
  @override
  Future<kakao.OAuthToken?> getToken() async => _token;
  @override
  Future<void> setToken(kakao.OAuthToken token) async {
    _token = token;
  }

  @override
  Future<void> clear() async {
    _token = null;
  }
}
