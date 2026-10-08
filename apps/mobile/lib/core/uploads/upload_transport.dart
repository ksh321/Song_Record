import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../features/auth/auth_session.dart';
import '../database/account_store.dart';

typedef UploadGuard = Future<void> Function();

final class UploadResponse {
  const UploadResponse(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'UploadResponse[REDACTED]';
}

final class UploadNetworkFailure implements Exception {
  const UploadNetworkFailure();
}

abstract interface class UploadTransport {
  Future<UploadResponse> authorize(
    UploadWork work,
    AuthSession session,
    UploadGuard guard,
  );
  Future<UploadResponse> renew(
    UploadWork work,
    AuthSession session,
    UploadGuard guard,
  );
  Future<int> put(
    Uri url,
    Map<String, List<String>> headers,
    Uint8List bytes,
    UploadGuard guard,
  );
}

final class HttpUploadTransport implements UploadTransport {
  HttpUploadTransport(
    this.base, {
    bool allowLocalHttp = false,
    this.timeout = const Duration(seconds: 30),
  }) {
    if ((base.scheme != 'https' &&
            !(allowLocalHttp &&
                base.scheme == 'http' &&
                {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host))) ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError('Invalid upload API endpoint');
    }
  }
  final Uri base;
  final Duration timeout;
  @override
  Future<UploadResponse> authorize(
    UploadWork w,
    AuthSession s,
    UploadGuard g,
  ) => _post(
    '/v1/recordings/${w.recordingId}/uploads',
    w.operationId,
    jsonEncode({'expected_size': w.size, 'sha256': w.sha256}),
    s,
    g,
  );
  @override
  Future<UploadResponse> renew(UploadWork w, AuthSession s, UploadGuard g) =>
      _post(
        '/v1/uploads/${w.attemptId}/renew-url',
        w.renewOperationId!,
        null,
        s,
        g,
      );
  Future<UploadResponse> _post(
    String path,
    String op,
    String? body,
    AuthSession session,
    UploadGuard guard,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await (() async {
        await guard();
        final request = await client.postUrl(base.resolve(path));
        await guard();
        request.followRedirects = false;
        request.headers.set('Authorization', 'Bearer ${session.accessToken}');
        request.headers.set('X-Device-Id', session.deviceId);
        request.headers.set('Idempotency-Key', op);
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(body));
        }
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          await guard();
          if (bytes.length + chunk.length > 65536) {
            throw const FormatException('Upload response too large');
          }
          bytes.addAll(chunk);
        }
        await guard();
        return UploadResponse(response.statusCode, utf8.decode(bytes));
      })().timeout(timeout);
    } on SocketException {
      throw const UploadNetworkFailure();
    } on HttpException {
      throw const UploadNetworkFailure();
    } on TimeoutException {
      throw const UploadNetworkFailure();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<int> put(
    Uri url,
    Map<String, List<String>> headers,
    Uint8List bytes,
    UploadGuard guard,
  ) async {
    if (url.scheme != 'https' ||
        !RegExp(r'^[a-f0-9]{32}\.r2\.cloudflarestorage\.com$')
            .hasMatch(url.host) ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      throw const FormatException('Invalid storage endpoint');
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await (() async {
        await guard();
        final request = await client.putUrl(url);
        await guard();
        request.followRedirects = false;
        request.contentLength = bytes.length;
        for (final entry in headers.entries) {
          final name = entry.key.toLowerCase();
          if (name == 'host') continue;
          if (name != 'content-type' &&
              name != 'x-amz-content-sha256' &&
              name != 'x-amz-checksum-sha256') {
            throw const FormatException('Unsupported storage header');
          }
          request.headers.set(entry.key, entry.value);
        }
        for (var offset = 0; offset < bytes.length; offset += 262144) {
          await guard();
          request.add(
            Uint8List.sublistView(
              bytes,
              offset,
              (offset + 262144).clamp(0, bytes.length),
            ),
          );
          await request.flush();
        }
        await guard();
        final response = await request.close();
        await response.drain<void>();
        await guard();
        return response.statusCode;
      })().timeout(timeout);
    } on SocketException {
      throw const UploadNetworkFailure();
    } on HttpException {
      throw const UploadNetworkFailure();
    } on TimeoutException {
      throw const UploadNetworkFailure();
    } finally {
      client.close(force: true);
    }
  }
}
