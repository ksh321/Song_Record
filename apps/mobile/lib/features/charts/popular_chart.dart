import 'dart:async';

import 'package:flutter/foundation.dart';

import '../search/karaoke_search.dart';

enum ChartPeriod {
  daily('일간'),
  weekly('주간'),
  monthly('월간');

  const ChartPeriod(this.label);
  final String label;
}

class ChartScope {
  const ChartScope(this.brand, this.period);
  final KaraokeBrand brand;
  final ChartPeriod period;
  String get brandCode => brand == KaraokeBrand.tj ? 'TJ' : 'KY';
  String get sourceUrl =>
      'https://api.manana.kr/karaoke/popular/${brand == KaraokeBrand.tj ? 'tj' : 'kumyoung'}/${period.name}.json';
  @override
  bool operator ==(Object other) =>
      other is ChartScope && brand == other.brand && period == other.period;
  @override
  int get hashCode => Object.hash(brand, period);
}

class ChartItem {
  const ChartItem({
    required this.position,
    required this.number,
    required this.title,
    required this.artist,
    this.sourceToken,
  });
  final int position;
  final String number, title, artist;
  final String? sourceToken;
}

class PublishedChart {
  PublishedChart({
    required this.scope,
    required this.fetchedAt,
    required this.revision,
    required this.stale,
    required List<ChartItem> items,
  }) : items = List.unmodifiable(items);
  final ChartScope scope;
  final DateTime fetchedAt;
  final int revision;
  final bool stale;
  final List<ChartItem> items;
  factory PublishedChart.fromJson(ChartScope expected, Object? raw) {
    if (raw is! Map ||
        raw['brand'] != expected.brandCode ||
        raw['period'] != expected.period.name.toUpperCase() ||
        raw['provider'] != 'MANANA' ||
        raw['source_url'] != expected.sourceUrl ||
        raw['stale'] is! bool ||
        raw['revision'] is! int ||
        (raw['revision'] as int) < 1 ||
        raw['fetched_at'] is! String ||
        raw['items'] is! List) {
      throw const FormatException('Invalid published chart');
    }
    final time = raw['fetched_at'] as String;
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(time)) {
      throw const FormatException('Missing collection timezone');
    }
    final fetched = DateTime.parse(time).toUtc();
    final items = <ChartItem>[];
    final numbers = <String>{};
    for (final row in raw['items'] as List) {
      if (row is! Map ||
          row['position'] != items.length + 1 ||
          row['number'] is! String ||
          !RegExp(r'^[0-9]{1,20}$').hasMatch(row['number'] as String) ||
          !numbers.add(row['number'] as String) ||
          row['title'] is! String ||
          (row['title'] as String).trim().isEmpty ||
          (row['title'] as String).runes.length > 200 ||
          row['artist'] is! String ||
          (row['artist'] as String).trim().isEmpty ||
          (row['artist'] as String).runes.length > 200) {
        throw const FormatException('Invalid chart item');
      }
      final token = row['source_token'];
      if (expected.brand == KaraokeBrand.tj
          ? token is! String || !token.startsWith('s1.') || token.length > 8192
          : token != null) {
        throw const FormatException('Invalid chart source evidence');
      }
      items.add(
        ChartItem(
          position: row['position'] as int,
          number: row['number'] as String,
          title: row['title'] as String,
          artist: row['artist'] as String,
          sourceToken: token as String?,
        ),
      );
    }
    if (items.isEmpty) {
      throw const FormatException('Empty chart cannot be published');
    }
    return PublishedChart(
      scope: expected,
      fetchedAt: fetched,
      revision: raw['revision'] as int,
      stale: raw['stale'] as bool,
      items: items,
    );
  }
}

class ChartFailure implements Exception {
  const ChartFailure(this.message, {this.code = 'CHART_UNAVAILABLE'});
  final String message, code;
  @override
  String toString() => message;
}

typedef ChartLoader = Future<PublishedChart> Function(ChartScope scope);

enum ChartPhase { waiting, loading, ready, unavailable, error }

class PopularChartController extends ChangeNotifier {
  PopularChartController(this.load);
  final ChartLoader load;
  ChartScope scope = const ChartScope(KaraokeBrand.tj, ChartPeriod.monthly);
  ChartPhase phase = ChartPhase.waiting;
  PublishedChart? chart;
  String? message;
  int _requestId = 0;
  bool _disposed = false;
  int get requestId => _requestId;
  Future<void> change({KaraokeBrand? brand, ChartPeriod? period}) async {
    if (_disposed) return;
    scope = ChartScope(brand ?? scope.brand, period ?? scope.period);
    final expected = scope;
    final id = ++_requestId;
    chart = null;
    message = null;
    phase = ChartPhase.loading;
    notifyListeners();
    try {
      final result = await load(expected);
      if (_disposed || id != _requestId || scope != expected) return;
      if (result.scope != expected || result.items.isEmpty) {
        throw const ChartFailure('차트 조건이 일치하지 않아요. 다시 시도해 주세요.');
      }
      chart = result;
      phase = ChartPhase.ready;
    } catch (e) {
      if (_disposed || id != _requestId) return;
      chart = null;
      message = e is ChartFailure
          ? e.message
          : '차트를 불러오지 못했어요. 내 곡과 녹음은 계속 사용할 수 있어요.';
      phase = e is ChartFailure && e.code == 'CHART_SOURCE_UNAVAILABLE'
          ? ChartPhase.unavailable
          : ChartPhase.error;
    }
    if (!_disposed) notifyListeners();
  }

  void clearForAccount() {
    if (_disposed) return;
    ++_requestId;
    chart = null;
    message = '로그인한 계정을 확인해 주세요.';
    phase = ChartPhase.waiting;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_requestId;
    super.dispose();
  }
}
