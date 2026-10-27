import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/database/local_models.dart';
import '../../core/domain/identifiers.dart';
import '../../core/sync/local_repository.dart';
import '../auth/auth_session.dart';

class TrashFailure implements Exception {
  const TrashFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class TrashApi {
  Future<Map<String, dynamic>> call(
    String method,
    String path,
    Map<String, Object?>? body,
    String? operation,
  );
}

abstract interface class TrashJournal {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
  Future<void> clear();
}

class SecureTrashJournal implements TrashJournal {
  SecureTrashJournal(String environment, String owner)
    : key = 'trash-command:$environment:${UuidValue(owner).value}';
  final String key;
  final storage = const FlutterSecureStorage();
  @override
  Future<Map<String, dynamic>?> read() async {
    final raw = await storage.read(key: key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> value) =>
      storage.write(key: key, value: jsonEncode(value));
  @override
  Future<void> clear() => storage.delete(key: key);
}

class HttpTrashApi implements TrashApi {
  HttpTrashApi(
    this.base,
    this.session,
    this.requireCurrent, {
    bool allowLocalHttp = false,
  }) {
    if (base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.scheme != 'https' &&
            !(allowLocalHttp &&
                base.scheme == 'http' &&
                {'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host)))) {
      throw ArgumentError('Trusted API endpoint required');
    }
  }
  final Uri base;
  final Future<AuthSession> Function() session;
  final void Function() requireCurrent;
  @override
  Future<Map<String, dynamic>> call(
    String method,
    String path,
    Map<String, Object?>? body,
    String? operation,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      return await (() async {
        requireCurrent();
        final auth = await session();
        requireCurrent();
        final req = await client.openUrl(method, base.resolve(path));
        requireCurrent();
        req.followRedirects = false;
        req.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${auth.accessToken}',
        );
        req.headers.set('X-Device-Id', auth.deviceId);
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (operation != null) req.headers.set('Idempotency-Key', operation);
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.add(utf8.encode(jsonEncode(body)));
        }
        final res = await req.close();
        final bytes = <int>[];
        await for (final part in res) {
          if (bytes.length + part.length > 1048576) {
            throw const TrashFailure('서버 응답을 확인하지 못했어요. 같은 요청으로 다시 확인해 주세요.');
          }
          bytes.addAll(part);
        }
        requireCurrent();
        if (res.statusCode != 200 && res.statusCode != 202) {
          // No raw provider response, credentials or object keys enter the UI.
          if ({400, 401, 403, 404, 409, 410, 422}.contains(res.statusCode)) {
            throw TrashRejected(res.statusCode);
          }
          throw const TrashFailure('결과를 확인하지 못했어요. 같은 요청으로 다시 확인해 주세요.');
        }
        final expectedStatus = method == 'POST' && path.endsWith('/purge')
            ? 202
            : 200;
        if (res.statusCode != expectedStatus) {
          throw const TrashFailure('처리 결과를 다시 확인해 주세요.');
        }
        final value = jsonDecode(utf8.decode(bytes));
        if (value is! Map<String, dynamic>) throw const FormatException();
        return value;
      })().timeout(const Duration(seconds: 20));
    } on SocketException {
      throw const TrashFailure('인터넷 연결을 확인해 주세요. 원본 파일은 유지돼요.');
    } on TimeoutException {
      throw const TrashFailure('응답이 늦어 결과를 확인하지 못했어요. 같은 요청으로 다시 확인해 주세요.');
    } on FormatException {
      throw const TrashFailure('서버 결과 형식을 확인하지 못했어요. 같은 요청으로 다시 확인해 주세요.');
    } finally {
      client.close(force: true);
    }
  }
}

class TrashRejected extends TrashFailure {
  TrashRejected(this.status)
    : super(
        status == 409
            ? '상태가 바뀌었거나 삭제 처리 중이에요. 새로 확인해 주세요.'
            : status == 401
            ? '다시 로그인해 주세요.'
            : '복원 가능한 항목과 서버 보관 기간을 확인해 주세요.',
      );
  final int status;
}

DateTime serverTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$')
          .hasMatch(value) ||
      parsed == null ||
      parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
    throw const FormatException('Invalid server time');
  }
  return parsed;
}

class TrashBatch {
  TrashBatch.fromJson(Map<String, dynamic> value)
    : id = UuidValue(value['batch_id'] as String).value,
      revision = value['revision'] as int,
      mode = value['mode'] as String,
      deleted = serverTime(value['deleted_at'] as String),
      expires = serverTime(value['purge_after'] as String),
      items = (value['items'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList() {
    if (revision < 1 ||
        !deleted.isUtc ||
        !expires.isUtc ||
        expires.difference(deleted) != const Duration(days: 7) ||
        !{'SONG_ONLY', 'SONG_AND_RECORDINGS', 'RECORDING'}.contains(mode)) {
      throw const FormatException('Invalid batch');
    }
    for (final item in items) {
      UuidValue(item['id'] as String);
      if (item['lifecycle_state'] != null &&
          !{
            'ACTIVE',
            'TRASHED',
            'PURGE_PENDING',
            'PURGED',
          }.contains(item['lifecycle_state'])) {
        throw const FormatException('Invalid lifecycle');
      }
      if (item['lifecycle_state'] != null) {
        item['state'] = item['lifecycle_state'];
      }
      if (!{
        'SONG',
        'RECORDING',
        'PLAYLIST_ITEM',
      }.contains(item['entity_type'])) {
        throw const FormatException('Invalid member');
      }
    }
  }
  final String id, mode;
  final int revision;
  final DateTime deleted, expires;
  final List<Map<String, dynamic>> items;
}

abstract interface class TrashActions {
  Future<Map<String, dynamic>> preview(String song);
  Future<void> trashSong(String song, String mode, String version);
  Future<void> trashRecording(String recording, bool confirmed);
  Future<Map<String, dynamic>> page(String? cursor);
  Future<Map<String, dynamic>> mutate(
    TrashBatch batch,
    List<String>? ids,
    bool purge,
  );
  Future<Map<String, dynamic>?> pending();
  Future<Map<String, dynamic>> retry();
}

class TrashWorkflow implements TrashActions {
  TrashWorkflow({
    required this.repository,
    required this.api,
    required this.journal,
    required this.requireCurrent,
    required this.wakeSync,
  });
  final LocalRepository repository;
  final TrashApi api;
  final TrashJournal journal;
  final void Function() requireCurrent, wakeSync;
  static final _inFlight = <String>{};
  String get _journalKey => journal is SecureTrashJournal
      ? (journal as SecureTrashJournal).key
      : identityHashCode(journal).toString();
  bool get busy => _inFlight.contains(_journalKey);
  @override
  Future<Map<String, dynamic>> preview(String song) async {
    requireCurrent();
    final result = await api.call(
      'GET',
      '/v1/songs/${UuidValue(song).value}/delete-preview',
      null,
      null,
    );
    requireCurrent();
    if (result['preview_version'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$')
            .hasMatch(result['preview_version'] as String) ||
        [
          'recording_count',
          'server_bytes',
          'pinned_count',
        ].any((key) => result[key] is! int || (result[key] as int) < 0)) {
      throw const TrashFailure('삭제 정보를 다시 확인해 주세요.');
    }
    return result;
  }

  Future<void> queue(
    LocalEntity entity,
    String id,
    Map<String, Object?> command,
  ) async {
    requireCurrent();
    final copy = await repository.read(entity, UuidValue(id).value);
    requireCurrent();
    if (copy == null ||
        copy.tombstone ||
        copy.serverJson == null ||
        (copy.localJson != null &&
            canonicalJson(
                  jsonDecode(copy.localJson!) as Map<String, dynamic>,
                ) !=
                canonicalJson(
                  jsonDecode(copy.serverJson!) as Map<String, dynamic>,
                ))) {
      throw const TrashFailure('동기화를 완료한 뒤 삭제해 주세요.');
    }
    final expected = jsonDecode(copy.serverJson!) as Map<String, dynamic>;
    final save = repository.prepareTrash(
      entity: entity,
      expected: expected,
      revision: copy.revision,
      command: command,
    );
    await save();
    requireCurrent();
    wakeSync();
  }

  @override
  Future<void> trashSong(String song, String mode, String version) =>
      queue(LocalEntity.song, song, {'mode': mode, 'preview_version': version});
  @override
  Future<void> trashRecording(String recording, bool confirmed) async {
    requireCurrent();
    final copy = await repository.read(LocalEntity.recording, recording);
    requireCurrent();
    if (copy == null) throw const TrashFailure('녹음을 확인하지 못했어요.');
    await queue(LocalEntity.recording, recording, {
      'base_revision': copy.revision,
      'pin_release_confirmed': confirmed,
    });
  }

  @override
  Future<Map<String, dynamic>> page(String? cursor) async {
    requireCurrent();
    final result = await api.call(
      'GET',
      '/v1/trash?limit=50${cursor == null ? '' : '&cursor=${UuidValue(cursor).value}'}',
      null,
      null,
    );
    requireCurrent();
    if (result['items'] is! List ||
        result['next_cursor'] != null && result['next_cursor'] is! String) {
      throw const FormatException('Invalid page');
    }
    for (final v in result['items'] as List) {
      final batch = TrashBatch.fromJson(Map<String, dynamic>.from(v as Map));
      for (final item in v['items'] as List) {
        if (!{'SONG', 'RECORDING'}.contains(item['entity_type'])) continue;
        final copy = await repository.read(
          item['entity_type'] == 'SONG'
              ? LocalEntity.song
              : LocalEntity.recording,
          item['id'] as String,
        );
        requireCurrent();
        if (copy?.serverJson != null) {
          final row = jsonDecode(copy!.serverJson!) as Map;
          item['title'] =
              row['title'] ?? row['title_snapshot'] ?? item['title'];
          item['artist'] =
              row['artist'] ?? row['artist_snapshot'] ?? item['artist'];
          item['recorded_at'] = row['recorded_at'] ?? item['recorded_at'];
          item['state'] = item['lifecycle_state'] ?? row['lifecycle_state'];
        }
      }
      if (batch.items.isEmpty) throw const FormatException('Empty batch');
    }
    if (result['next_cursor'] != null) {
      UuidValue(result['next_cursor'] as String);
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>?> pending() async {
    requireCurrent();
    final result = await journal.read();
    requireCurrent();
    return result;
  }

  @override
  Future<Map<String, dynamic>> mutate(
    TrashBatch batch,
    List<String>? ids,
    bool purge,
  ) async {
    if (busy) throw const TrashFailure('진행 중인 요청을 기다려 주세요.');
    _inFlight.add(_journalKey);
    try {
      requireCurrent();
      if (await pending() != null) {
        throw const TrashFailure('결과 미확인 요청을 먼저 다시 확인해 주세요.');
      }
      if (ids != null &&
          (ids.isEmpty ||
              ids.toSet().length != ids.length ||
              ids.any(
                (id) => !batch.items.any(
                  (v) => v['id'] == id && v['entity_type'] != 'PLAYLIST_ITEM',
                ),
              ))) {
        throw const TrashFailure('항목을 선택해 주세요.');
      }
      final command = {
        'path': '/v1/trash/${batch.id}/${purge ? 'purge' : 'restore'}',
        'operation': UuidValue.random().value,
        'body': {'base_revision': batch.revision, 'item_ids': ?ids},
      };
      await journal.write(command);
      requireCurrent();
      return await send(command);
    } finally {
      _inFlight.remove(_journalKey);
    }
  }

  @override
  Future<Map<String, dynamic>> retry() async {
    if (busy) throw const TrashFailure('요청 처리 중이에요.');
    _inFlight.add(_journalKey);
    try {
      final command = await pending();
      if (command == null) throw const TrashFailure('미확인 요청이 없어요.');
      return await send(command);
    } finally {
      _inFlight.remove(_journalKey);
    }
  }

  Future<Map<String, dynamic>> send(Map<String, dynamic> command) async {
    final path = command['path'] as String;
    final match = RegExp(r'^/v1/trash/([0-9a-f-]{36})/(restore|purge)$')
        .firstMatch(path);
    if (match == null) throw const TrashFailure('저장된 요청을 확인하지 못했어요.');
    final id = UuidValue(match.group(1)!).value;
    final op = UuidValue(command['operation'] as String).value;
    final body = Map<String, Object?>.from(command['body'] as Map);
    requireCurrent();
    try {
      final result = await api.call('POST', path, body, op);
      requireCurrent();
      if (result['batch_id'] != id ||
          result['revision'] is! int ||
          (result['revision'] as int) != (body['base_revision'] as int) + 1) {
        throw const TrashFailure('응답을 다시 확인해 주세요.');
      }
      if (match.group(2) == 'restore') {
        if (result['restored'] is! List ||
            result['skipped'] is! List ||
            result['pin_reselection_required'] is! bool) {
          throw const TrashFailure('복원 결과를 다시 확인해 주세요.');
        }
      } else {
        if (result['state'] != 'PURGE_PENDING' || result['job_id'] is! String) {
          throw const TrashFailure('삭제 상태를 다시 확인해 주세요.');
        }
        UuidValue(result['job_id'] as String);
      }
      await journal.clear();
      requireCurrent();
      wakeSync();
      return result;
    } on TrashRejected catch (error) {
      // 401/403 may come from auth before an already committed retry; keep its identity.
      if ({400, 404, 409, 410, 422}.contains(error.status)) {
        requireCurrent();
        await journal.clear();
      }
      rethrow;
    }
  }
}
