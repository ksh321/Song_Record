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
