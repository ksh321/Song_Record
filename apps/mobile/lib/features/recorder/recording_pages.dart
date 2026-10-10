import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/files/recording_file_status.dart';
import 'recording_filter.dart';
import 'recording_order.dart';

final class RecordingCursor {
  const RecordingCursor(
    this.scope,
    this.generation,
    this.conditions,
    this.source,
    this.lastId,
  );
  final String scope, conditions, source, lastId;
  final int generation;
}

final class RecordingPages {
  RecordingPages({this.limit = 50}) {
    if (limit < 1 || limit > 100) throw RangeError.range(limit, 1, 100);
  }
  final int limit;
  String scope = '', _sourceFingerprint = '', _conditions = '';
  int generation = 0;
  List<Map<String, dynamic>> _source = [], ordered = [], visible = [];
  RecordingFilter _filter = RecordingFilter();
  RecordingSort _sort = RecordingSort.newest;
  int get total => ordered.length;
  int get unknownFiles {
    if (!_filter.values.containsKey('file')) return 0;
    final base = RecordingFilter(Map.of(_filter.values)..remove('file'));
    return _source.where(base.matches).where((r) {
      final s = r['_file_status'] as RecordingFileStatus?;
      return s == null ||
          s.device == DeviceAudioState.unknown ||
          s.serverState == 'UNKNOWN';
    }).length;
  }

  RecordingCursor? get cursor => visible.length < total && visible.isNotEmpty
      ? RecordingCursor(
          scope,
          generation,
          _conditions,
          _sourceFingerprint,
          visible.last['id'] as String,
        )
      : null;
  void replace(
    List<Map<String, dynamic>> rows,
    String ownerScope, {
    bool complete = true,
    DateTime? lastSync,
  }) {
    final serial =
        rows.map((row) {
            final s = row['_file_status'] as RecordingFileStatus?;
            return {
              ...row,
              '_file_status': s == null
                  ? null
                  : {
                      'device': s.device.name,
                      'server': s.serverState,
                      'blocked': s.blockedReason,
                      'information': s.information.name,
                    },
            };
          }).toList()
          ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'rows': serial,
              'complete': complete,
              'last_sync': lastSync?.toIso8601String(),
            }),
          ),
        )
        .toString();
    if (scope == ownerScope && _sourceFingerprint == fingerprint) return;
    scope = ownerScope;
    _sourceFingerprint = fingerprint;
    _source = rows;
    _reset();
  }

  void select(RecordingFilter filter, RecordingSort sort) {
    filter.validate();
    final keys = filter.values.keys.toList()..sort();
    final condition = jsonEncode({
      'filter': {for (final k in keys) k: filter.values[k]},
      'sort': sort.name,
      'key': 'SR-SORT-1',
      'timezone': 'Asia/Seoul',
    });
    if (condition == _conditions) return;
    _conditions = condition;
    _filter = filter;
    _sort = sort;
    _reset();
  }

  void _reset() {
    ++generation;
    ordered = sortRecordings(_source.where(_filter.matches).toList(), _sort);
    visible = ordered.take(limit).toList();
  }

  void next(RecordingCursor after) {
    final current = cursor;
    if (current == null ||
        after.scope != scope ||
        after.generation != generation ||
        after.conditions != _conditions ||
        after.source != _sourceFingerprint ||
        after.lastId != current.lastId) {
      throw StateError('Recording cursor changed; reload first page');
    }
    // The last ordered key (unique id within a frozen generation), never an offset supplied by a caller.
    final next = ordered
        .skipWhile((row) => row['id'] != after.lastId)
        .skip(1)
        .take(limit);
    visible = [...visible, ...next];
  }
}
