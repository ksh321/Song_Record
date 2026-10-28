import 'dart:convert';

import '../../core/database/local_models.dart';
import '../../core/domain/input_validation.dart';
import '../../core/sync/local_repository.dart';
import '../../core/sync/mutation_request.dart';
import '../../core/sync/playlist_library_order_receipt.dart';
import '../search/search_intent.dart';

final class PlaylistLibrary {
  PlaylistLibrary(this.repository);
  final LocalRepository repository;

  Future<QueuedMutation?> pendingOrder() async {
    for (final mutation in await repository.pendingWork()) {
      if (mutation.entity != LocalEntity.playlist) continue;
      final request = MutationRequest.prepare(mutation);
      if (request != null && isPlaylistLibraryOrder(request)) return mutation;
    }
    return null;
  }

  Future<QueuedMutation?> rejectedOrder() async {
    for (final mutation in await repository.pendingWork()) {
      if (mutation.entity != LocalEntity.playlist ||
          mutation.state != 'CONFLICT') {
        continue;
      }
      final response = jsonDecode(mutation.serverResponse ?? '{}') as Map;
      if (response['status'] == 409 &&
          response['code'] == 'PLAYLIST_ORDER_CHANGED') {
        return mutation;
      }
    }
    return null;
  }

  Future<void> reorderLibrary(
    List<Map<String, dynamic>> baseline,
    List<String> ids,
  ) async {
    final current = await load();
    if ((await repository.pendingWork()).any(
      (m) => m.entity == LocalEntity.playlist,
    )) {
      throw StateError('목록의 이전 변경을 먼저 동기화해 주세요.');
    }
    final originals = {for (final row in baseline) row['id']: row};
    if (baseline.isEmpty ||
        baseline.length > 1000 ||
        ids.length != baseline.length ||
        ids.toSet().length != ids.length ||
        !ids.every(originals.containsKey) ||
        current.length != baseline.length ||
        current.any(
          (row) =>
              originals[row['id']]?['local_base_revision'] !=
              row['local_base_revision'],
        )) {
      throw StateError('목록이 바뀌었어요. 다시 열어 순서를 변경해 주세요.');
    }
    final anchor = baseline.first;
    final value = _payload(anchor);
    final command = repository.preparePatch(
      entity: LocalEntity.playlist,
      entityId: anchor['id'] as String,
      baseRevision: anchor['local_base_revision'] as int,
      draft: value,
      changes: {
        'ordered_playlists': [
          for (final id in ids)
            {'id': id, 'base_revision': originals[id]!['local_base_revision']},
        ],
      },
    );
    await repository.saveCheckedEdit(command, value);
  }

  Future<void> removeItem(Map<String, dynamic> row, String itemId) async {
    final id = row['id'] as String;
    if ((await repository.pendingWork()).any(
      (m) => m.entity == LocalEntity.playlist && m.entityId == id,
    )) {
      throw StateError('이 목록의 이전 변경을 먼저 동기화해 주세요.');
    }
    if (!(await items(id)).any((item) => item['id'] == itemId)) {
      throw StateError('목록 항목이 변경됐어요.');
    }
    final value = _payload(row);
    await repository.saveCheckedEdit(
      repository.preparePatch(
        entity: LocalEntity.playlist,
        entityId: id,
        baseRevision: row['local_base_revision'] as int,
        draft: value,
        changes: {'remove_item_id': itemId},
      ),
      value,
    );
  }

  Future<void> reorder(Map<String, dynamic> row, List<String> ids) async {
    final id = row['id'] as String;
    if ((await repository.pendingWork()).any(
      (m) => m.entity == LocalEntity.playlist && m.entityId == id,
    )) {
      throw StateError('이 목록의 이전 변경을 먼저 동기화해 주세요.');
    }
    final current = (await items(id)).map((i) => i['id']).toSet();
    if (ids.toSet().length != ids.length ||
        ids.length != current.length ||
        !current.containsAll(ids)) {
      throw StateError('목록 항목이 변경됐어요.');
    }
    final value = _payload(row);
    await repository.saveCheckedEdit(
      repository.preparePatch(
        entity: LocalEntity.playlist,
        entityId: id,
        baseRevision: row['local_base_revision'] as int,
        draft: value,
        changes: {'ordered_item_ids': ids},
      ),
      value,
    );
  }

  Future<void> addSelection(String id, KaraokeSelection selection) async {
    if (selection.intent.purpose != SearchPurpose.playlist ||
        selection.intent.playlistId != id ||
        selection.intent.returnRoute != '/playlists/$id') {
      throw StateError('선택한 목록이 변경됐어요.');
    }
    if ((await repository.pendingWork()).any(
      (m) =>
          m.entity == LocalEntity.playlist &&
          m.entityId == id &&
          m.operation != LocalOperation.create,
    )) {
      throw StateError('이 목록의 이전 변경을 먼저 동기화해 주세요.');
    }
    // A catalog candidate does not recreate or restore the reserved Song.
    // The owned Song is restored only after a separate confirmation.
    final row = (await load()).singleWhere((p) => p['id'] == id);
    await addCandidate(row, selection.candidate.sourceToken)();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final rows = await repository.activePlaylists();
    final pending = await pendingOrder();
    if (pending == null ||
        !{'PENDING', 'SENDING', 'RETRY'}.contains(pending.state)) {
      return rows;
    }
    final order =
        (jsonDecode(pending.payload) as Map)['ordered_playlists'] as List;
    final positions = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      positions[order[i]['id'] as String] = i;
    }
    if (rows.length == order.length &&
        rows.every((row) {
          final index = positions[row['id']];
          return index != null &&
              row['local_base_revision'] == order[index]['base_revision'];
        })) {
      rows.sort((a, b) => positions[a['id']]!.compareTo(positions[b['id']]!));
    }
    return rows;
  }

  Future<Map<String, PlaylistSummary>> summaries(
    List<Map<String, dynamic>> playlists,
  ) async {
    final available = {for (final song in await songs()) song['id']: song};
    final grouped = await repository.playlistSummaryItems();
    final result = <String, PlaylistSummary>{};
    for (final playlist in playlists) {
      final id = playlist['id'] as String;
      result[id] = PlaylistSummary.fromItems(
        grouped[id] ?? const [],
        available,
      );
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> items(String id) =>
      repository.playlistItems(id);
  Future<List<Map<String, dynamic>>> songs() =>
      repository.watchActiveSongs().first;

  Future<void> addRegisteredMany(
    String playlistId,
    Iterable<String> selected, {
    Future<void> Function()? afterEach,
  }) async {
    final ids = <String>[];
    final entries = await items(playlistId);
    if ((await repository.pendingWork()).any(
      (m) =>
          m.entity == LocalEntity.playlist &&
          m.entityId == playlistId &&
          m.operation != LocalOperation.create,
    )) {
      throw StateError('이 목록의 이전 변경을 먼저 동기화해 주세요.');
    }
    final available = {for (final song in await songs()) song['id']: song};
    for (final id in selected.toSet()) {
      final song = available[id];
      if (song == null) throw StateError('선택한 내 곡 상태가 바뀌었어요.');
      final key = song['source_type'] == 'TJ'
          ? 'tj:${song['tj_number']}'
          : 'manual:$id';
      if (entries.any(
        (item) => item['song_id'] == id || item['entry_key'] == key,
      )) {
        continue;
      }
      ids.add(id);
    }
    if (ids.isEmpty) return;
    if (ids.length > 100) throw ArgumentError('한 번에 100곡까지 선택해 주세요.');
    final row = (await load()).singleWhere((p) => p['id'] == playlistId);
    final value = _payload(row);
    final command = repository.preparePatch(
      entity: LocalEntity.playlist,
      entityId: playlistId,
      baseRevision: row['local_base_revision'] as int,
      draft: value,
      changes: {'song_ids': ids},
    );
    await repository.saveCheckedEdit(command, value);
    await afterEach?.call();
  }

  Future<void> Function() addCandidate(
    Map<String, dynamic> row,
    String sourceToken,
  ) {
    if (sourceToken.trim().isEmpty || sourceToken.length > 8192) {
      throw ArgumentError('검증된 TJ 검색 결과를 다시 선택해 주세요.');
    }
    final value = _payload(row);
    final command = repository.preparePatch(
      entity: LocalEntity.playlist,
      entityId: row['id'] as String,
      baseRevision: row['local_base_revision'] as int,
      draft: value,
      changes: {'source_token': sourceToken},
    );
    return () => repository.saveCheckedEdit(command, value);
  }

  Future<void> Function() linkCandidate(
    Map<String, dynamic> row,
    String itemId,
    String songId,
  ) {
    final value = _payload(row);
    final command = repository.preparePatch(
      entity: LocalEntity.playlist,
      entityId: row['id'] as String,
      baseRevision: row['local_base_revision'] as int,
      draft: value,
      changes: {'item_id': itemId, 'song_id': songId},
    );
    return () => repository.saveCheckedEdit(command, value);
  }

  Future<void> Function() addRegistered(
    Map<String, dynamic> row,
    String songId,
  ) {
    final value = _payload(row);
    final command = repository.preparePatch(
      entity: LocalEntity.playlist,
      entityId: row['id'] as String,
      baseRevision: row['local_base_revision'] as int,
      draft: value,
      changes: {'song_id': songId},
    );
    return () => repository.saveCheckedEdit(command, value);
  }

  String _name(String input) {
    final value = validateInput(InputField.playlist, input);
    if (!value.isValid) throw ArgumentError('목록 이름은 1~100자로 입력해 주세요.');
    return value.value;
  }

  Future<void> Function() create(String input, {String icon = 'music'}) {
    final name = _name(input);
    final command = repository.prepareCreate(
      entity: LocalEntity.playlist,
      draft: {'name': name, 'icon': icon, 'deleted_at': null},
      changes: {'name': name, 'icon': icon},
    );
    return () => repository.save(command);
  }

  Future<Map<String, dynamic>> createVisible(
    String input, {
    String icon = 'music',
  }) async {
    final name = _name(input);
    final command = repository.prepareCreate(
      entity: LocalEntity.playlist,
      draft: {'name': name, 'icon': icon, 'deleted_at': null},
      changes: {'name': name, 'icon': icon},
    );
    await repository.save(command);
    final saved = await repository.read(LocalEntity.playlist, command.entityId);
    if (saved == null || saved.tombstone) {
      throw StateError('Playlist no longer available');
    }
    final raw = saved.localJson ?? saved.serverJson;
    if (raw == null) throw StateError('Missing saved playlist');
    final value = jsonDecode(raw) as Map<String, dynamic>;
    if (value['id'] != command.entityId ||
        value['deleted_at'] != null ||
        value['status'] == 'DELETED') {
      throw StateError('Playlist changed');
    }
    return {...value, 'local_base_revision': saved.revision};
  }

  Map<String, Object?> _payload(Map<String, dynamic> row) =>
      {...row}..remove('local_base_revision');
  Future<void> Function() rename(Map<String, dynamic> row, String input) {
    final value = _payload(row), name = _name(input);
    if (value['name'] == name) return () async {};
    final command = repository.preparePatch(
      entity: LocalEntity.playlist,
      entityId: row['id'] as String,
      baseRevision: row['local_base_revision'] as int,
      draft: {...value, 'name': name},
      changes: {'name': name},
    );
    return () => repository.saveCheckedEdit(command, value);
  }

  Future<void> Function() changeIcon(Map<String, dynamic> row, String icon) {
    if (!{
      'music',
      'mic',
      'heart',
      'star',
      'headphones',
      'sun',
    }.contains(icon)) {
      throw ArgumentError('Invalid icon');
    }
    final value = _payload(row);
    final command = repository.preparePatch(
      entity: LocalEntity.playlist,
      entityId: row['id'] as String,
      baseRevision: row['local_base_revision'] as int,
      draft: {...value, 'icon': icon},
      changes: {'name': row['name'], 'icon': icon},
    );
    return () => repository.saveCheckedEdit(command, value);
  }

  Future<void> Function() delete(Map<String, dynamic> row) {
    final value = _payload(row), revision = row['local_base_revision'] as int;
    final prepared = repository.preparePatch(
      entity: LocalEntity.playlist,
      entityId: row['id'] as String,
      baseRevision: revision,
      draft: {...value, 'deleted_at': DateTime.now().toUtc().toIso8601String()},
      changes: {'delete': true},
    );
    final command = LocalEdit(
      opId: prepared.opId,
      entity: LocalEntity.playlist,
      entityId: prepared.entityId,
      operation: LocalOperation.purge,
      baseRevision: revision,
      draft: {...value, 'deleted_at': DateTime.now().toUtc().toIso8601String()},
      changes: {'base_revision': revision},
    );
    return () => repository.saveCheckedEdit(command, value);
  }
}

/// Display-only data from the same account's active songs and visible items.
final class PlaylistSummary {
  const PlaylistSummary(this.count, this.preview);
  final int count;
  final String preview;

  factory PlaylistSummary.fromItems(
    List<Map<String, dynamic>> items,
    Map<dynamic, Map<String, dynamic>> songs,
  ) {
    final titles = <String>[];
    for (final item in items) {
      if (item['song_id'] != null) {
        final song = songs[item['song_id']];
        // Do not resurrect a trashed song using its candidate snapshot.
        if (song != null) titles.add(song['title'] as String);
      } else if (item['candidate_brand'] == 'TJ' &&
          item['candidate_snapshot'] is Map) {
        titles.add((item['candidate_snapshot'] as Map)['title'] as String);
      }
    }
    return PlaylistSummary(
      titles.length,
      titles.isEmpty ? '첫 곡을 담아보세요' : titles.take(2).join(' · '),
    );
  }
}
