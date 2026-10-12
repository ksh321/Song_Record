import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../auth/auth_session.dart';

/// Only application-owned settings routes receive the current account token.
class SettingsApi {
  SettingsApi(
    this.base,
    this.session,
    this.requireCurrent, {
    bool local = false,
  }) {
    if (base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.scheme != 'https' &&
            !(local &&
                base.scheme == 'http' &&
                {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host))) {
      throw ArgumentError('Invalid settings origin');
    }
  }
  final Uri base;
  final Future<AuthSession> Function() session;
  final void Function() requireCurrent;
  Future<dynamic> get(String path) async {
    if (!{
      '/v1/storage',
      '/v1/pins',
      '/v1/tags',
      '/v1/conditions',
    }.contains(path)) {
      throw ArgumentError('Unknown settings route');
    }
    requireCurrent();
    final auth = await session();
    requireCurrent();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final request = await client.getUrl(base.resolve(path));
        request.followRedirects = false;
        request.headers.set('Authorization', 'Bearer ${auth.accessToken}');
        request.headers.set('X-Device-Id', auth.deviceId);
        request.headers.set('Cache-Control', 'no-store');
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const FormatException('Settings response too large');
          }
          bytes.addAll(chunk);
        }
        requireCurrent();
        if (response.statusCode != 200) throw const SettingsUnavailable();
        return jsonDecode(utf8.decode(bytes));
      })().timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }
}

class SettingsUnavailable implements Exception {
  const SettingsUnavailable();
  @override
  String toString() => '설정 정보를 읽지 못했어요. 연결과 로그인 상태를 확인해 주세요.';
}
