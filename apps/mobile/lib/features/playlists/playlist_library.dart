import '../../core/database/local_models.dart';
import '../../core/domain/input_validation.dart';
import '../../core/sync/local_repository.dart';

final class PlaylistLibrary {
  PlaylistLibrary(this.repository);
  final LocalRepository repository;
  Future<List<Map<String, dynamic>>> load() => repository.activePlaylists();
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

  Future<void> Function() create(String input) {
    final name = _name(input);
    final command = repository.prepareCreate(
      entity: LocalEntity.playlist,
      draft: {'name': name, 'deleted_at': null},
      changes: {'name': name},
    );
    return () => repository.save(command);
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
