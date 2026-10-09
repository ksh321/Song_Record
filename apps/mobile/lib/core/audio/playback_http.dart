import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/auth/auth_session.dart';
import '../domain/identifiers.dart';
import 'playback_ticket.dart';

final class PlaybackRequestFailure implements Exception {
  const PlaybackRequestFailure();
  @override
  String toString() => 'PlaybackRequestFailure[REDACTED]';
}

final class HttpPlaybackUrls implements PlaybackUrlProvider {
  HttpPlaybackUrls(
    this.base,
    this.session, {
    this.allowLocalHttp = false,
    this.timeout = const Duration(seconds: 30),
  }) {
    final local =
        allowLocalHttp &&
        base.scheme == 'http' &&
        {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host);
    if (!(base.scheme == 'https' || local) ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError('Invalid playback API');
    }
  }
  final Uri base;
  final Future<AuthSession> Function() session;
  final bool allowLocalHttp;
  final Duration timeout;
  @override
  Future<PlaybackTicket> issue(
    String recording,
    Future<void> Function() guard,
  ) async {
    final id = UuidValue(recording).value;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await (() async {
        await guard();
        final auth = await session();
        await guard();
        final request = await client.postUrl(
          base.resolve('/v1/recordings/$id/playback-url'),
        );
        request.followRedirects = false;
        request.headers.set('Authorization', 'Bearer ${auth.accessToken}');
        request.headers.set('X-Device-Id', auth.deviceId);
        final response = await request.close();
        if (response.statusCode != 200 || response.contentLength > 16384) {
          throw const PlaybackRequestFailure();
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 16384) throw const PlaybackRequestFailure();
        }
        await guard();
        final value = jsonDecode(utf8.decode(bytes));
        if (value is! Map<String, dynamic> ||
            value['user_id'] != auth.userId ||
            value['recording_id'] != id) {
          throw const PlaybackRequestFailure();
        }
        return PlaybackTicket(
          owner: value['user_id'] as String,
          recording: id,
          generation: value['generation'] as String,
          checksum: value['sha256'] as String,
          size: value['size_bytes'] as int,
          revision: value['cloud_revision'] as int,
          url: Uri.parse(value['url'] as String),
          expiresAt: DateTime.parse(value['expires_at'] as String).toUtc(),
          allowLocalHttp: allowLocalHttp,
        );
      })().timeout(timeout);
    } catch (_) {
      throw const PlaybackRequestFailure();
    } finally {
      client.close(force: true);
    }
  }
}
