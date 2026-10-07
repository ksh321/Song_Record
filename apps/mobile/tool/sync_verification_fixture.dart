import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/sync/canonical_conflict_plan.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/conflict_review.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/core/sync/snapshot_response.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/sync/change_feed_sync_backend.dart';
import 'package:song_record/features/sync/snapshot_sync_backend.dart';
import 'package:song_record/features/sync/sync_controller.dart';

String fixtureId(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
Map<String, Object?> fixtureTag(String id, String name, int revision) => {
  'id': id,
  'name': name,
  'revision': revision,
  'archived_at': null,
  'updated_at': '2026-10-01T00:00:00Z',
};

Map<String, Object?> fixtureSong(String id, int revision, {String note = '서버 메모'}) => {
  'id': id, 'revision': revision, 'updated_at': '2026-10-01T00:00:00Z',
  'source_type': 'TJ', 'tj_number': '12345', 'title': '합성 곡',
  'artist': '합성 가수', 'version_code': 'NORMAL', 'tier': null, 'note': note,
  'lifecycle_state': 'ACTIVE', 'representative_key_mode': null,
  'representative_key_shift': null, 'representative_recording_id': null,
};

/// No HTTP implementation or credentials: responses are synthetic and local.
final class VerificationTransport implements MutationTransport {
  VerificationTransport(this.status, this.responseDelay);
  final int? status;
  final Future<void> Function() responseDelay;
  int calls = 0;
  final started = Completer<void>();
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() current,
  ) async {
    current();
    calls++;
    if (!started.isCompleted) started.complete();
    if (status != null) {
      await responseDelay();
      current();
      return MutationResponse(status!, '{"error":{"code":"UNAUTHENTICATED"}}');
    }
    final body = jsonDecode(request.body) as Map;
    if (request.mutation.entity == LocalEntity.song) {
      await responseDelay();
      current();
      return MutationResponse(200, jsonEncode({
        ...fixtureSong(request.mutation.entityId, request.mutation.baseRevision + 1),
        ...Map<String, dynamic>.from(body)..remove('base_revision'),
        'revision': request.mutation.baseRevision + 1,
      }));
    }
    return MutationResponse(
      200,
      jsonEncode(
        fixtureTag(request.mutation.entityId, body['name'] as String,
          request.mutation.baseRevision + 1),
      ),
    );
  }
}

final class SyncVerificationFixture {
  SyncVerificationFixture._(
    this.manager,
    this.store,
    this.controller,
    this.transport,
    this.run,
    this.snapshots,
  );
  final AccountStoreManager manager;
  final AccountStore store;
  final SyncController controller;
  final VerificationTransport transport;
  final Directory run;
  final VerificationSnapshots? snapshots;
  String get runName => run.uri.pathSegments.where((s) => s.isNotEmpty).last;

  static Future<List<String>> savedRuns(Directory root) async {
    if (!await root.exists()) return [];
    final names = <String>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory &&
          await File('${entry.path}/run.json').exists()) {
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (RegExp(r'^sync-verification-[A-Za-z0-9_-]+$').hasMatch(name)) {
          names.add(name);
        }
      }
    }
    names.sort();
    return names;
  }

  /// New runs get a fresh child directory; reopening never seeds or clears it.
  static Future<SyncVerificationFixture> create(
    Directory root, {
    int? authenticationStatus,
    Future<void> Function()? responseDelay,
    bool canonical = false,
    bool changeOnReview = false,
    bool resync = false,
    bool expirePage = false,
    DateTime Function()? clock,
    String? resumeRun,
  }) async {
    if (authenticationStatus != null &&
        authenticationStatus != 401 &&
        authenticationStatus != 403) {
      throw ArgumentError('Only 401/403 verification scenarios are supported');
    }
    await root.create(recursive: true);
    final reopening = resumeRun != null;
    late final Directory run;
    if (reopening) {
      if (!(await savedRuns(root)).contains(resumeRun)) {
        throw StateError('Unknown isolated verification run');
      }
      run = Directory('${root.path}/$resumeRun');
      final config = jsonDecode(await File('${run.path}/run.json').readAsString())
          as Map<String, dynamic>;
      if (config['version'] != 1 || config['resync'] != true ||
          config['owner'] != fixtureId(1) || config['expire_page'] is! bool) {
        throw StateError('Invalid verification run');
      }
      resync = true;
      expirePage = config['expire_page'] as bool;
      canonical = false;
      changeOnReview = false;
      authenticationStatus = null;
      final paths = await AccountPaths.create(run, fixtureId(1), AppEnvironment.dev);
      if (!await (await paths.databaseFile()).exists()) {
        throw StateError('Verification database is missing');
      }
    } else {
      run = await root.createTemp('sync-verification-');
    }
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => run,
      temporaryDirectory: () async => run,
      clock: clock,
    );
    try {
      final store = await manager.openAccount(fixtureId(1));
      final repository = LocalRepository(store);
      final transport = VerificationTransport(
        authenticationStatus,
        responseDelay ?? () => Future<void>.delayed(const Duration(seconds: 8)),
      );
      if (!reopening && canonical) {
        await repository.save(repository.prepareCreate(
          entity: LocalEntity.song, entityId: fixtureId(20),
          draft: fixtureSong(fixtureId(20), 0, note: '이 기기 개인 메모'),
          changes: {'id': fixtureId(20), 'source_type': 'TJ',
            'source_token': 'synthetic-proof', 'note': '이 기기 개인 메모'},
        ));
        final request = (await store.claimMutation())!;
        await store.applyCanonicalSongReceipt(request, MutationResponse(200, jsonEncode({
          'created': false, 'canonical_song_id': fixtureId(21),
          'song': fixtureSong(fixtureId(21), 2),
        })));
      } else if (!reopening && authenticationStatus == null) {
        await repository.save(
          repository.prepareCreate(
            entity: LocalEntity.tag,
            entityId: fixtureId(10),
            draft: {'name': '처음 이름'},
            changes: {'name': '처음 이름'},
          ),
        );
        await store.acknowledgeMutation(
          (await store.claimMutation())!,
          fixtureTag(fixtureId(10), '처음 이름', 1),
        );
        await repository.save(
          repository.preparePatch(
            entity: LocalEntity.tag,
            entityId: fixtureId(10),
            baseRevision: 1,
            draft: fixtureTag(fixtureId(10), '이 기기 이름', 1),
            changes: {'name': '이 기기 이름'},
          ),
        );
        await store.deferMutation(
          (await store.claimMutation())!,
          'CONFLICT',
          'REVISION_CONFLICT',
          status: 409,
          serverSnapshot: fixtureTag(fixtureId(10), '서버 이름', 2),
        );
      } else if (!reopening) {
        for (final n in [10, 11]) {
          await repository.save(
            repository.prepareCreate(
              entity: LocalEntity.tag,
              entityId: fixtureId(n),
              draft: {'name': '검증 항목 $n'},
              changes: {'name': '검증 항목 $n'},
            ),
          );
        }
      }
      final auth = AuthSession(
        userId: fixtureId(1),
        deviceId: fixtureId(2),
        accessToken: 'synthetic-only',
        refreshToken: 'synthetic-only',
        accessExpiresAt: DateTime.utc(2099),
        refreshExpiresAt: DateTime.utc(2099),
      );
      SyncBackend backend = RepositorySyncBackend(repository, transport, () async => auth);
      VerificationSnapshots? snapshots;
      if (resync) {
        final now = clock ?? DateTime.now;
        if (!reopening) {
          final old = verificationSnapshot(owner: store.userId, token: fixtureId(80),
            cursor: 7, now: now(), rows: {'TAG': [fixtureTag(fixtureId(10), '처음 이름', 1)]});
          await installVerificationSnapshot(store, old);
        }
        snapshots = await VerificationSnapshots.open(run, store.userId, now,
          expirePage: expirePage, restoring: reopening);
        backend = SnapshotSyncBackend(
          receiver: SnapshotReceiver(store: store, transport: snapshots,
            newOperationId: () => UuidValue.random().value, clock: now),
          session: () async => auth, now: now,
          outgoing: ChangeFeedSyncBackend(
            receiver: ChangeFeedReceiver(store: store,
              transport: VerificationChanges(), isSessionCurrent: (_) => true,
              newOperationId: () => UuidValue.random().value),
            outgoing: backend, session: () async => auth, now: now,
            allowInitialRestart: true),
        );
      }
      final controller = SyncController(
        backend,
        conflicts: changeOnReview
            ? _ChangingReviewActions(repository, () async {
                // Only this newly-created synthetic run is touched. This hook
                // simulates an incoming server change after the screen reads.
                store.requireActive();
                final paths = await AccountPaths.create(run, fixtureId(1), AppEnvironment.dev);
                final db = AccountDatabase(NativeDatabase(await paths.databaseFile()),
                  userId: fixtureId(1), environment: AppEnvironment.dev);
                try {
                  await db.verifyReady();
                  await db.transaction(() async {
                    store.requireActive();
                    await db.customStatement(
                      "UPDATE metadata_copies SET server_revision=3,server_payload=? WHERE entity_type='SONG' AND entity_id=?",
                      [canonicalJson(fixtureSong(fixtureId(21), 3, note: '뒤에 도착한 서버 메모')), fixtureId(21)],
                    );
                    store.requireActive();
                  });
                } finally { await db.close(); }
              })
            : repository,
      );
      await controller.refresh();
      if (resync && !reopening) {
        final marker = File('${run.path}/run.pending');
        await marker.writeAsString(jsonEncode({'version': 1, 'resync': true,
          'owner': store.userId, 'expire_page': expirePage}), flush: true);
        await marker.rename('${run.path}/run.json');
      }
      return SyncVerificationFixture._(manager, store, controller, transport, run, snapshots);
    } catch (_) {
      await manager.logout();
      rethrow;
    }
  }

  Future<void> close() async {
    controller.dispose();
    await manager.logout();
    await snapshots?.close();
  }
}

/// Complete synthetic framing shared by installed verification and HTTP tests.
/// No production files or server fixtures are read by the installed app.
Map<String, dynamic> verificationSnapshot({required String owner,
  required String token, required int cursor, required DateTime now,
  required Map<String, List<Map<String, Object?>>> rows}) {
  final ready = DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch,
    isUtc: true,
  );
  final expiry = ready.add(const Duration(minutes: 30)).toIso8601String();
  final all = {...rows, 'USER_SYNC_STATE': <Map<String, Object?>>[
    {'user_id': owner, 'last_change_seq': cursor}]};
  final pages = <Map<String, dynamic>>[];
  final bytes = BytesBuilder()..add(ascii.encode('SongRecord:snapshot-manifest:1'));
  void number(int n, int size) {
    final data = ByteData(size);
    if (size == 8) { data.setInt64(0, n); } else { data.setInt32(0, n); }
    bytes.add(data.buffer.asUint8List());
  }
  number(cursor, 8);
  for (final entity in snapshotEntities) {
    final entries = <Map<String, Object?>>[];
    for (final row in all[entity] ?? <Map<String, Object?>>[]) {
      final payload = {...row, 'user_id': owner};
      final id = (row['id'] ?? row['recording_id'] ?? owner) as String;
      final raw = canonicalJson(payload), ordinal = entries.length + 1;
      entries.add({'ordinal': ordinal, 'resource_id': id,
        'payload': payload, 'canonical_payload': raw});
      final name = ascii.encode(entity), data = utf8.encode(raw);
      number(name.length, 4); bytes.add(name); number(ordinal, 8);
      bytes.add(UuidValue(id).bytes); number(data.length, 4); bytes.add(data);
    }
    pages.add({'snapshot_token': token,
      'snapshot_cursor': cursor, 'expires_at': expiry, 'entity': entity,
      'entries': entries, 'next_cursor': null});
  }
  return {'manifest': {'snapshot_token': token, 'status': 'READY',
    'schema_version': 1, 'snapshot_cursor': cursor,
    'captured_at': ready.toIso8601String(), 'ready_at': ready.toIso8601String(),
    'expires_at': expiry, 'manifest_hash': sha256.convert(bytes.takeBytes()).toString(),
    'entity_counts': {for (final p in pages) p['entity'] as String: (p['entries'] as List).length}},
    'pages': pages};
}

Future<void> installVerificationSnapshot(AccountStore store, Map<String, dynamic> fixture) async {
  final token = fixture['manifest']['snapshot_token'] as String;
  await store.beginSnapshotDownload(token, jsonEncode(fixture['manifest']));
  for (final page in fixture['pages'] as List<dynamic>) {
    await store.appendSnapshotPage(token, page['entity'] as String, 0, jsonEncode(page));
  }
  await store.verifySnapshotDownload(token);
  await store.applySnapshotDownload(token);
}

final class VerificationChanges implements ChangeFeedTransport {
  @override
  Future<ChangeFeedResponse> send(ChangeFeedRequest request, AuthSession session,
      void Function() fence) async {
    fence();
    if (request.after == 7) {
      return const ChangeFeedResponse(409, '{"error":{"code":"CURSOR_EXPIRED"}}');
    }
    return ChangeFeedResponse(200, jsonEncode({'after_seq': request.after,
      'next_seq': request.after, 'head_seq': request.after,
      'has_more': false, 'changes': <Object?>[]}));
  }
}

final class VerificationSnapshots implements SnapshotTransport {
  VerificationSnapshots._(this.run, this.owner, this.now, this.expirePage,
      this._revision, this._state);
  final Directory run;
  final String owner;
  final DateTime Function() now;
  final bool expirePage;
  int _revision;
  Map<String, dynamic> _state;
  Future<void> _idle = Future<void>.value();
  bool _closed = false;

  Future<void> close() {
    _closed = true;
    return _idle;
  }

  static Future<VerificationSnapshots> open(Directory run, String owner,
      DateTime Function() now, {required bool expirePage, bool restoring = false}) async {
    final records = <File>[];
    await for (final entry in run.list(followLinks: false)) {
      if (entry is File && RegExp(r'/snapshot-\d{12}\.json$').hasMatch(entry.uri.path)) {
        records.add(entry);
      }
    }
    records.sort((a, b) => a.path.compareTo(b.path));
    if (records.isEmpty && restoring) {
      throw StateError('Verification server state is missing');
    }
    final state = records.isEmpty
        ? <String, dynamic>{'version': 1, 'owner': owner, 'expire_page': expirePage,
            'operations': <String, dynamic>{}, 'expired_tokens': <String>[],
            'pages': 0, 'injected': false}
        : jsonDecode(await records.last.readAsString()) as Map<String, dynamic>;
    if (state['version'] != 1 || state['owner'] != owner ||
        state['expire_page'] != expirePage || state['operations'] is! Map ||
        state['expired_tokens'] is! List || state['pages'] is! int ||
        state['injected'] is! bool) {
      throw StateError('Invalid verification server state');
    }
    final revision = records.isEmpty ? 0 : int.parse(
      RegExp(r'snapshot-(\d{12})\.json$').firstMatch(records.last.path)!.group(1)!);
    final server = VerificationSnapshots._(run, owner, now, expirePage, revision, state);
    if (records.isEmpty) await server._commit(state);
    return server;
  }

  // Publish a new immutable record only after its bytes have been flushed.
  // A killed writer can leave a .pending file, never a partially published state.
  Future<void> _commit(Map<String, dynamic> next) async {
    final revision = _revision + 1;
    final target = '${run.path}/snapshot-${revision.toString().padLeft(12, '0')}.json';
    final temporary = File('${run.path}/${UuidValue.random().value}.pending');
    await temporary.writeAsString(jsonEncode(next), flush: true);
    await temporary.rename(target);
    _revision = revision;
    _state = next;
  }

  @override
  Future<SnapshotHttpResponse> send(SnapshotHttpRequest request, AuthSession session,
      void Function() fence) {
    final result = _idle.then((_) {
      if (_closed) throw StateError('Verification server is closed');
      return _send(request, session, fence);
    });
    _idle = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<SnapshotHttpResponse> _send(SnapshotHttpRequest request, AuthSession session,
      void Function() fence) async {
    fence();
    if (session.userId != owner) throw StateError('Verification account changed');
    final operations = Map<String, dynamic>.from(_state['operations'] as Map);
    if (request.method == 'POST') {
      final operation = request.operationId!;
      if (!operations.containsKey(operation)) {
        final token = UuidValue.random().value;
        operations[operation] = verificationSnapshot(owner: owner, token: token,
          cursor: 10, now: now(),
          rows: {'TAG': [fixtureTag(fixtureId(10), '재수신한 서버 이름', 3)]});
        await _commit({..._state, 'operations': operations});
      }
      fence();
      final snapshot = operations[operation] as Map<String, dynamic>;
      final token = (snapshot['manifest'] as Map)['snapshot_token'] as String;
      return SnapshotHttpResponse(202, jsonEncode({'operation_id': request.operationId,
        'snapshot_token': token, 'status': 'BUILDING', 'status_url': '/v1/sync/snapshots/$token'}));
    }
    final token = request.path.split('/').last;
    final matches = operations.values.cast<Map<String, dynamic>>().where(
      (s) => (s['manifest'] as Map)['snapshot_token'] == token);
    if (matches.length != 1) throw StateError('Unknown verification snapshot');
    final current = matches.single;
    final manifest = current['manifest'] as Map<String, dynamic>;
    final expired = List<String>.from(_state['expired_tokens'] as List);
    const expiredResponse = SnapshotHttpResponse(
      410, '{"error":{"code":"SNAPSHOT_EXPIRED"}}');
    if (expired.contains(token) ||
        !now().toUtc().isBefore(DateTime.parse(manifest['expires_at'] as String))) {
      return expiredResponse;
    }
    final entity = request.query['entity'];
    if (entity == null) return SnapshotHttpResponse(200, jsonEncode(manifest));
    final pages = _state['pages'] as int;
    final inject = expirePage && _state['injected'] == false && pages == 3;
    if (inject) expired.add(token);
    await _commit({..._state, 'pages': pages + 1, 'expired_tokens': expired,
      'injected': inject || _state['injected'] == true});
    fence();
    if (inject) {
      return expiredResponse;
    }
    return SnapshotHttpResponse(200, jsonEncode((current['pages'] as List<dynamic>)
      .singleWhere((dynamic p) => p['entity'] == entity)));
  }
}

final class _ChangingReviewActions implements ConflictActions, CanonicalConflictActions {
  _ChangingReviewActions(this.repository, this.advance);
  final LocalRepository repository;
  final Future<void> Function() advance;
  bool changed = false;
  @override
  Future<ConflictReview> review(String opId) => repository.review(opId);
  @override
  Future<void> resolve(ConflictReview review, Map<String, ConflictChoice> choices) => repository.resolve(review, choices);
  @override
  Future<List<CanonicalConflictReview>> canonicalCandidates() => repository.canonicalCandidates();
  @override
  Future<CanonicalConflictReview> reviewCanonical(String intentId) async {
    final result = await repository.reviewCanonical(intentId);
    if (!changed) { changed = true; await advance(); }
    return result;
  }
  @override
  Future<void> resolveCanonical(CanonicalConflictReview review, ConflictChoice choice) => repository.resolveCanonical(review, choice);
}
