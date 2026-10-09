import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../auth/auth_session.dart';
import 'karaoke_search.dart';

class HttpKaraokeSearch {
  HttpKaraokeSearch(this.base, {this.allowLocalHttp = false}) {
    if (base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.scheme != 'https' &&
            !(allowLocalHttp &&
                base.scheme == 'http' &&
                {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host))) {
      throw ArgumentError('Search requires HTTPS or local development');
    }
  }
  final Uri base;
  final bool allowLocalHttp;

  Future<List<KaraokeCandidate>> search(
    KaraokeQuery query,
    AuthSession session,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final uri = base
            .resolve('/v1/karaoke/search')
            .replace(
              queryParameters: {
                'brand': query.brand == KaraokeBrand.tj ? 'TJ' : 'KY',
                'kind': query.kind.name.toUpperCase(),
                'q': query.text.trim(),
              },
            );
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set('Authorization', 'Bearer ${session.accessToken}');
        request.headers.set('X-Device-Id', session.deviceId);
        request.headers.set('Accept', 'application/json');
        request.headers.set('Cache-Control', 'no-store');
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const FormatException('Response too large');
          }
          bytes.addAll(chunk);
        }
        final json = jsonDecode(utf8.decode(bytes));
        if (response.statusCode != 200) {
          final error = json is Map ? json['error'] : null;
          final code = error is Map && error['code'] is String
              ? error['code'] as String
              : 'SEARCH_UNAVAILABLE';
          throw KaraokeFailure(
            response.statusCode == 401
                ? '다시 로그인해 주세요.'
                : response.statusCode == 429
                ? '검색이 많아요. 잠시 후 다시 시도해 주세요.'
                : '외부 검색에 연결할 수 없어요. 입력은 유지됩니다.',
            code: code,
          );
        }
        if (json is! Map || json['results'] is! List) {
          throw const FormatException('Invalid response');
        }
        final rows = json['results'] as List;
        if (rows.length > 1000) throw const FormatException('Too many results');
        final seen = <String>{};
        final result = <KaraokeCandidate>[];
        for (final value in rows) {
          if (value is! Map) throw const FormatException('Invalid result');
          String text(String name) {
            final x = value[name];
            if (x is! String || x.isEmpty) {
              throw const FormatException('Missing field');
            }
            return x;
          }

          final brand = text('brand');
          final number = text('number');
          if (brand != (query.brand == KaraokeBrand.tj ? 'TJ' : 'KY') ||
              !RegExp(r'^[0-9]{1,20}$').hasMatch(number) ||
              !seen.add(number)) {
            throw const FormatException('Candidate identity mismatch');
          }
          final title = text('title'),
              artist = text('artist'),
              token = text('source_token');
          final provider = text('provider'), source = text('source_ref');
          if (title.runes.length > 200 ||
              artist.runes.length > 200 ||
              token.length > 8192 ||
              provider != 'MANANA' ||
              source != 'manana:${brand == 'TJ' ? 'tj' : 'kumyoung'}:$number') {
            throw const FormatException('Invalid candidate evidence');
          }
          final matched = value['matched_song_id'];
          if (matched != null && (matched is! String || brand == 'KY')) {
            throw const FormatException('Invalid account match');
          }
          result.add(
            KaraokeCandidate(
              brand: query.brand,
              number: number,
              title: title,
              artist: artist,
              provider: provider,
              sourceRef: source,
              sourceToken: token,
              expiresAt: DateTime.parse(text('expires_at')).toUtc(),
              matchedSongId: matched as String?,
            ),
          );
        }
        return List<KaraokeCandidate>.unmodifiable(result);
      })().timeout(const Duration(seconds: 5));
    } on KaraokeFailure {
      rethrow;
    } catch (_) {
      throw const KaraokeFailure('검색에 연결할 수 없어요. 입력은 유지됩니다.');
    } finally {
      client.close(force: true);
    }
  }
}
