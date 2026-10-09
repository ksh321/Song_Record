import 'dart:async';

import 'package:flutter/foundation.dart';

enum KaraokeBrand { tj, ky }

enum KaraokeKind { title, artist, number }

enum SearchPhase { idle, waiting, loading, results, empty, error }

class KaraokeQuery {
  const KaraokeQuery(this.brand, this.kind, this.text);
  final KaraokeBrand brand;
  final KaraokeKind kind;
  final String text;
}

class KaraokeCandidate {
  const KaraokeCandidate({
    required this.brand,
    required this.number,
    required this.title,
    required this.artist,
    required this.provider,
    required this.sourceRef,
    required this.sourceToken,
    required this.expiresAt,
    this.matchedSongId,
  });
  final KaraokeBrand brand;
  final String number, title, artist, provider, sourceRef, sourceToken;
  final DateTime expiresAt;
  final String? matchedSongId;
  @override
  String toString() => 'KaraokeCandidate[REDACTED]';
}

class KaraokeFailure implements Exception {
  const KaraokeFailure(this.message, {this.code = 'SEARCH_UNAVAILABLE'});
  final String message, code;
  @override
  String toString() => message;
}

typedef KaraokeLoader = Future<List<KaraokeCandidate>> Function(
  KaraokeQuery query,
);

/// Invalidate at edit time, including the interval before the next debounce fires.
class KaraokeSearchController extends ChangeNotifier {
  KaraokeSearchController(this.load);
  final KaraokeLoader load;
  KaraokeQuery query = const KaraokeQuery(
    KaraokeBrand.tj,
    KaraokeKind.title,
    '',
  );
  SearchPhase phase = SearchPhase.idle;
  List<KaraokeCandidate> results = const [];
  String? message;
  Timer? _timer;
  int _requestId = 0;
  bool _disposed = false;
  int get requestId => _requestId;

  void change({KaraokeBrand? brand, KaraokeKind? kind, String? text}) {
    if (_disposed) return;
    query = KaraokeQuery(
      brand ?? query.brand,
      kind ?? query.kind,
      text ?? query.text,
    );
    final id = ++_requestId;
    _timer?.cancel();
    results = const [];
    message = null;
    phase = query.text.trim().isEmpty ? SearchPhase.idle : SearchPhase.waiting;
    notifyListeners();
    if (phase == SearchPhase.waiting) {
      _timer = Timer(const Duration(milliseconds: 400), () => _run(id, query));
    }
  }

  void retry() {
    if (_disposed || query.text.trim().isEmpty) return;
    _timer?.cancel();
    unawaited(_run(++_requestId, query));
  }

  void clearForAccount() {
    _timer?.cancel();
    ++_requestId;
    query = const KaraokeQuery(KaraokeBrand.tj, KaraokeKind.title, '');
    phase = SearchPhase.idle;
    results = const [];
    message = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(int id, KaraokeQuery requested) async {
    if (_disposed || id != _requestId) return;
    final trimmed = requested.text.trim();
    if (trimmed.runes.length > 200 ||
        trimmed.runes.any((r) => r < 32 || r == 127) ||
        requested.kind == KaraokeKind.number &&
            !RegExp(r'^[0-9]{1,20}$').hasMatch(trimmed)) {
      phase = SearchPhase.error;
      message = '검색 조건을 확인해 주세요.';
      notifyListeners();
      return;
    }
    phase = SearchPhase.loading;
    results = const [];
    message = null;
    notifyListeners();
    try {
      final found = await load(
        KaraokeQuery(requested.brand, requested.kind, trimmed),
      );
      if (_disposed || id != _requestId) return;
      if (found.any((c) => c.brand != requested.brand)) {
        throw const KaraokeFailure('검색 응답의 브랜드를 확인하지 못했어요.');
      }
      results = List.unmodifiable(found);
      phase = results.isEmpty ? SearchPhase.empty : SearchPhase.results;
    } catch (e) {
      if (_disposed || id != _requestId) return;
      results = const [];
      phase = SearchPhase.error;
      message = e is KaraokeFailure ? e.message : '검색에 연결할 수 없어요. 입력은 유지됩니다.';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    ++_requestId;
    super.dispose();
  }
}
