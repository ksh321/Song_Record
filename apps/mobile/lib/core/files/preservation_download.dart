import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../features/auth/auth_session.dart';
import 'local_preservation.dart';

final class PreservationNetworkFailure implements Exception {
  const PreservationNetworkFailure();
}

final class PreservationFileUnavailable implements Exception {
  const PreservationFileUnavailable();
}

final class HttpPreservationDownload implements PreservationDownload {
  HttpPreservationDownload(
    this.base,
    this.session, {
    this.allowLocalHttp = false,
    this.timeout = const Duration(seconds: 30),
  }) {
    if (!_api(base) ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError('Invalid preservation endpoint');
    }
  }
  final Uri base;
  final Future<AuthSession> Function() session;
  final bool allowLocalHttp;
  final Duration timeout;
  bool _local(Uri u) =>
      allowLocalHttp &&
      u.scheme == 'http' &&
      {'localhost', '127.0.0.1', '10.0.2.2'}.contains(u.host);
  bool _api(Uri u) => u.scheme == 'https' || _local(u);
  @override
  Future<Uint8List> download(
    PreservationObject object,
    Future<void> Function() guard,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    try {
      return await (() async {
        await guard();
        final url = await _ticket(client, object, guard);
        await guard();
        final get = await client.getUrl(url);
        get.followRedirects = false;
        // API authentication must never be forwarded to object storage.
        final file = await get.close();
        if (file.statusCode != 200) throw const PreservationNetworkFailure();
        final bytes = await _read(file, object.size);
        await guard();
        if (bytes.length != object.size) {
          throw const PreservationNetworkFailure();
        }
        // Signed object URLs can outlive deletion. Check current API state again.
        await _ticket(client, object, guard);
        await guard();
        return bytes;
      })().timeout(timeout);
    } on PreservationFileUnavailable {
      rethrow;
    } catch (_) {
      throw const PreservationNetworkFailure();
    } finally {
      client.close(force: true);
    }
  }

  Future<Uri> _ticket(
    HttpClient client,
    PreservationObject object,
    Future<void> Function() guard,
  ) async {
    final auth = await session();
    await guard();
    if (auth.userId != object.owner) {
      throw const PreservationNetworkFailure();
    }
    final request = await client.getUrl(
      base.resolve('/v1/recordings/${object.recording}/preservation-url'),
    );
    request.followRedirects = false;
    request.headers.set('Authorization', 'Bearer ${auth.accessToken}');
    request.headers.set('X-Device-Id', auth.deviceId);
    final response = await request.close();
    if (response.statusCode == 409) {
      final unavailable = jsonDecode(utf8.decode(await _read(response, 16384)));
      if (unavailable is Map &&
          unavailable['error'] is Map &&
          (unavailable['error'] as Map)['code'] == 'FILE_NOT_STORED') {
        throw const PreservationFileUnavailable();
      }
    }
    if (response.statusCode != 200) {
      throw const PreservationNetworkFailure();
    }
    final body = await _read(response, 16384);
    await guard();
    final ticket = jsonDecode(utf8.decode(body));
    if (ticket is! Map<String, dynamic> ||
        ticket['user_id'] != object.owner ||
        ticket['recording_id'] != object.recording ||
        ticket['generation'] != object.generation ||
        ticket['sha256'] != object.checksum ||
        ticket['size_bytes'] != object.size ||
        ticket['cloud_revision'] != object.revision ||
        !DateTime.parse(ticket['expires_at'] as String)
            .isAfter(DateTime.now().toUtc())) {
      throw const PreservationNetworkFailure();
    }
    final url = Uri.parse(ticket['url'] as String);
    if (!((url.scheme == 'https' &&
                url.host.endsWith('.r2.cloudflarestorage.com')) ||
            _local(url)) ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      throw const PreservationNetworkFailure();
    }
    await guard();
    return url;
  }

  Future<void> validateCurrent(
    PreservationObject object,
    Future<void> Function() guard,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    try {
      await _ticket(client, object, guard).timeout(timeout);
    } on PreservationFileUnavailable {
      rethrow;
    } catch (_) {
      throw const PreservationNetworkFailure();
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _read(HttpClientResponse response, int maximum) async {
    if (response.contentLength > maximum) {
      throw const PreservationNetworkFailure();
    }
    final builder = BytesBuilder(copy: false);
    var size = 0;
    await for (final chunk in response) {
      size += chunk.length;
      if (size > maximum) throw const PreservationNetworkFailure();
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
