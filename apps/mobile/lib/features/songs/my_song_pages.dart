import 'dart:convert';

import '../../core/widgets/sort_sheet.dart';
import 'my_song.dart';

/// Local-only cursor. Never accepted as an API cursor or across account scope.
final class MySongCursor {
  const MySongCursor(this.scope, this.generation, this.lastId);
  final String scope, lastId;
  final int generation;
}

final class MySongPages {
  List<MySong> _source = [], ordered = [];
  String _fingerprint = '', scope = '', query = '';
  SongSort sort = SongSort.recentlyAdded;
  bool grouped = false;
  int generation = 0, _end = 50;
  int get total => ordered.length;
  List<MySong> get visible => ordered.take(_end).toList();
  MySongCursor? get cursor => _end < total && _end > 0
      ? MySongCursor(scope, generation, ordered[_end - 1].view.id.value)
      : null;

  void replace(List<MySong> rows, String ownerScope) {
    final fingerprint = jsonEncode(rows.map((s) => s.payload).toList());
    if (fingerprint == _fingerprint && scope == ownerScope) return;
    _source = rows;
    _fingerprint = fingerprint;
    scope = ownerScope;
    _reset();
  }

  void select({
    required String search,
    required SongSort selectedSort,
    required bool tierView,
  }) {
    if (query == search && sort == selectedSort && grouped == tierView) return;
    query = search;
    sort = selectedSort;
    grouped = tierView;
    _reset();
  }

  void _reset() {
    ++generation;
    _end = 50;
    final matches = _source.where((s) => s.matches(query));
    ordered = grouped
        ? groupMySongs(matches, sort).values.expand((s) => s).toList()
        : orderMySongs(matches, sort);
  }

  void next(MySongCursor after) {
    final current = cursor;
    if (current == null ||
        after.scope != scope ||
        after.generation != generation ||
        after.lastId != current.lastId) {
      throw StateError(
        'Local song cursor is stale or belongs to another scope',
      );
    }
    _end += 50;
  }
}
