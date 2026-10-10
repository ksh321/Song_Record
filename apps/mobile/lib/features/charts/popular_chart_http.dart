import 'dart:convert';
import 'dart:io';

import '../auth/auth_session.dart';
import 'popular_chart.dart';

class HttpPopularChart {
  HttpPopularChart(this.base, {this.allowLocalHttp = false}) {
    if (base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.scheme != 'https' &&
            !(allowLocalHttp &&
                base.scheme == 'http' &&
                {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host))) {
      throw ArgumentError('Chart requires HTTPS or local development');
    }
  }
  final Uri base;
  final bool allowLocalHttp;
  Future<PublishedChart> read(ChartScope scope, AuthSession session) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final uri = base
            .resolve('/v1/charts/popular')
            .replace(
              queryParameters: {
                'brand': scope.brandCode,
                'period': scope.period.name.toUpperCase(),
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
        final raw = jsonDecode(utf8.decode(bytes));
        if (response.statusCode != 200) {
          final error = raw is Map ? raw['error'] : null;
          final code = error is Map && error['code'] is String
              ? error['code'] as String
              : 'CHART_UNAVAILABLE';
          throw ChartFailure(
            response.statusCode == 401
                ? '다시 로그인해 주세요.'
                : code == 'CHART_SOURCE_UNAVAILABLE'
                ? '선택한 브랜드·기간의 자료가 없어요. 잠시 뒤 다시 시도해 주세요.'
                : '차트 연결에 실패했어요. 내 곡과 녹음은 계속 사용할 수 있어요.',
            code: code,
          );
        }
        return PublishedChart.fromJson(scope, raw);
      })().timeout(const Duration(seconds: 5));
    } on ChartFailure {
      rethrow;
    } catch (_) {
      throw const ChartFailure('차트 연결에 실패했어요. 내 곡과 녹음은 계속 사용할 수 있어요.');
    } finally {
      client.close(force: true);
    }
  }
}
