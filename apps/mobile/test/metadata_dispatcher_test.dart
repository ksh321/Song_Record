import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_database.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

String id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
const time = '2026-09-29T00:00:00Z';
Map<String, Object?> tag(
  String target, {
  String name = 'tag',
  int revision = 1,
}) => {
  'id': target,
  'name': name,
  'revision': revision,
  'archived_at': null,
  'updated_at': time,
};

class RealHttpOverrides extends HttpOverrides {}

final class FakeTransport implements MutationTransport {
  FakeTransport(this.action);
  final Future<MutationResponse> Function(MutationRequest) action;
  int calls = 0;
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() current,
  ) {
    current();
    calls++;
    return action(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late LocalRepository repo;
  final owner = id(1);
  AuthSession auth(String user) => AuthSession(
    userId: user,
    deviceId: id(2),
    accessToken: 'test-access',
    refreshToken: 'test-refresh',
    accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
  );
  Future<AuthSession> session() async => auth(owner);
  Future<LocalEdit> createTag(int n) async {
    final edit = repo.prepareCreate(
      entity: LocalEntity.tag,
      entityId: id(n),
      draft: {'name': 'tag'},
      changes: {'name': 'tag'},
    );
    await repo.save(edit);
    return edit;
  }

  Future<AccountDatabase> raw() async {
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    final db = AccountDatabase(
      NativeDatabase(await paths.databaseFile()),
      userId: owner,
      environment: AppEnvironment.dev,
    );
    await db.verifyReady();
    return db;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sr-dispatch-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(owner);
    repo = LocalRepository(store);
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });

  test(
    '401 headers survive a stalled response body and stop this pass',
    () async {
      await createTag(10);
      await createTag(11);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var calls = 0;
      final listener = server.listen((request) async {
        calls++;
        await request.drain<void>();
        request.response.statusCode = 401;
        request.response.contentLength = 100;
        request.response.add([32]);
        await request.response.flush();
        // Leave the declared body incomplete to exercise the real timeout path.
      });
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          final transport = HttpMutationTransport(
            Uri.parse('http://127.0.0.1:${server.port}'),
            allowLocalHttp: true,
            timeout: const Duration(milliseconds: 500),
          );
          expect(
            await repo.dispatch(transport: transport, session: session),
            0,
          );
        }, RealHttpOverrides());
        expect(calls, 1);
        final pending = await repo.pending();
        expect(pending.map((m) => m.state), ['RETRY', 'PENDING']);
        expect(jsonDecode(pending.first.serverResponse!)['status'], 401);
      } finally {
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );

  for (final oversized in [false, true]) {
    test(
      'auth headers survive ${oversized ? 'oversized' : 'invalid UTF8'} body',
      () async {
        await createTag(10);
        await createTag(11);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var calls = 0;
        final listener = server.listen((request) async {
          calls++;
          await request.drain<void>();
          request.response.statusCode = oversized ? 403 : 401;
          request.response.add(oversized ? List.filled(1048577, 32) : [255]);
          try {
            await request.response.close();
          } catch (_) {
            /* client bounds body */
          }
        });
        try {
          await HttpOverrides.runWithHttpOverrides(() async {
            final transport = HttpMutationTransport(
              Uri.parse('http://127.0.0.1:${server.port}'),
              allowLocalHttp: true,
            );
            expect(
              await repo.dispatch(transport: transport, session: session),
              0,
            );
          }, RealHttpOverrides());
          expect(calls, 1);
          final pending = await repo.pending();
          expect(pending.map((m) => m.state), ['RETRY', 'PENDING']);
          expect(
            jsonDecode(pending.first.serverResponse!)['status'],
            oversized ? 403 : 401,
          );
          expect((await repo.retryStatus(pending.first.opId))!.mode, 'BLOCKED');
        } finally {
          await listener.cancel();
          await server.close(force: true);
        }
      },
    );
  }

  test(
    'real HTTP sends frozen body and headers and commits ACK without cursor',
    () async {
      final edit = await createTag(10);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<void>();
      final listener = server.listen((request) async {
        try {
          expect(request.method, 'POST');
          expect(request.uri.path, '/v1/tags');
          expect(request.headers.value('Idempotency-Key'), edit.opId);
          expect(request.headers.value('Authorization'), 'Bearer test-access');
          expect(request.headers.value('X-Device-Id'), id(2));
          expect(await utf8.decoder.bind(request).join(), edit.changesJson);
          request.response.statusCode = 201;
          request.response.write(jsonEncode(tag(edit.entityId)));
          await request.response.close();
          received.complete();
        } catch (e, s) {
          received.completeError(e, s);
        }
      });
      try {
        final transport = HttpMutationTransport(
          Uri.parse('http://127.0.0.1:${server.port}'),
          allowLocalHttp: true,
        );
        expect(
          await HttpOverrides.runWithHttpOverrides(
            () => repo.dispatch(transport: transport, session: session),
            RealHttpOverrides(),
          ),
          1,
        );
        await received.future;
        expect(await repo.pending(), isEmpty);
        expect((await repo.read(LocalEntity.tag, edit.entityId))!.revision, 1);
        expect(await store.readCursor(), isNull);
        final recovery = await store.recoveryData();
        expect(recovery, contains('metadata-v1'));
        expect(recovery, isNot(contains('test-access')));
        expect(recovery, isNot(contains('test-refresh')));
      } finally {
        await server.close(force: true);
        await listener.cancel();
      }
    },
  );

  test(
    'v1 upgrade preserves queue order, custom metadata and local file bytes',
    () async {
      final legacyOwner = id(40);
      final paths = await AccountPaths.create(
        root,
        legacyOwner,
        AppEnvironment.dev,
      );
      final file = await paths.databaseFile();
      final old = sqlite.sqlite3.open(file.path);
      old.execute(
        await File('test/fixtures/local_schema_v1.sql').readAsString(),
      );
      old.execute('PRAGMA user_version=1');
      old.execute("INSERT INTO local_account VALUES(1,?,'dev',1)", [
        legacyOwner,
      ]);
      old.execute(
        'INSERT INTO sync_cursors(singleton,user_id,updated_at) VALUES(1,?,1)',
        [legacyOwner],
      );
      for (final n in [52, 51]) {
        old.execute(
          "INSERT INTO metadata_copies(user_id,entity_type,entity_id,local_payload,updated_at) VALUES(?,'RECORDING_CONDITION',?,?,1)",
          [
            legacyOwner,
            id(n),
            jsonEncode({'id': id(n), 'name': 'old custom'}),
          ],
        );
        old.execute(
          "INSERT INTO local_mutations(op_id,user_id,entity_type,entity_id,operation,base_revision,payload,request_hash,created_at,updated_at) VALUES(?,?,'RECORDING_CONDITION',?,'CREATE',0,?,?,1,1)",
          [
            id(n + 100),
            legacyOwner,
            id(n),
            jsonEncode({'id': id(n), 'name': 'old custom'}),
            'a' * 64,
          ],
        );
      }
      old.close();
      final audio = await paths.checkedFile(paths.audioPath(id(70)));
      await audio.writeAsBytes([1, 3, 5, 7]);
      final upgraded = await manager.openAccount(legacyOwner);
      expect((await upgraded.pendingMutations()).map((m) => m.entityId), [
        id(52),
        id(51),
      ]);
      expect(
        (await upgraded.readMetadata(
          LocalEntity.recordingCondition,
          id(52),
        ))!.localJson,
        contains('old custom'),
      );
      expect(await audio.readAsBytes(), [1, 3, 5, 7]);
      expect(await upgraded.claimMutation(), isNull);
      expect(await upgraded.recoveryData(), contains('mutation_wire_requests'));
    },
  );

  test('create duplicate/canonical response preserves local input and server evidence', () async {
    final edit = await createTag(10);
    final transport = FakeTransport(
      (r) async => MutationResponse(
        200,
        jsonEncode(tag(id(11), name: 'server existing')),
      ),
    );
    expect(await repo.dispatch(transport: transport, session: session), 0);
    final pending = (await repo.pending()).single;
    expect(pending.state, 'CONFLICT');
    expect(jsonDecode(pending.serverResponse!)['current']['id'], id(11));
    final copy = (await repo.read(LocalEntity.tag, edit.entityId))!;
    expect(copy.revision, 0);
    expect(jsonDecode(copy.localJson!)['name'], 'tag');
  });

  test(
    'parent ACK unlocks child then recording PATCH accepts real server shape',
    () async {
      final songId = id(20), recordingId = id(21);
      final recording = {
        'id': recordingId,
        'metadata_state': 'DRAFT',
        'song_id': songId,
        'title_snapshot': null,
        'artist_snapshot': null,
        'version_code': 'NORMAL',
        'key_mode': null,
        'key_shift': null,
        'note': '',
        'recorded_at': time,
        'timezone_id': 'UTC',
        'timezone_offset_minutes': 0,
        'origin_device_id': id(2),
        'revision': 1,
        'link_revision': 1,
        'updated_at': time,
        'lifecycle_state': 'ACTIVE',
        'condition_code': null,
        'condition_name_snapshot': null,
      };
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.recording,
          entityId: recordingId,
          draft: recording,
          changes: {
            'metadata_state': 'DRAFT',
            'song_id': songId,
            'recorded_at': time,
            'timezone_id': 'UTC',
            'timezone_offset_minutes': 0,
          },
        ),
      );
      final song = {
        'id': songId,
        'revision': 1,
        'updated_at': time,
        'representative_key_mode': null,
        'representative_key_shift': null,
        'representative_recording_id': null,
        'source_type': 'MANUAL',
        'tj_number': null,
        'title': 'song',
        'artist': 'artist',
        'version_code': 'NORMAL',
        'tier': null,
        'note': '',
        'lifecycle_state': 'ACTIVE',
      };
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: songId,
          draft: song,
          changes: {
            'source_type': 'MANUAL',
            'title': 'song',
            'artist': 'artist',
            'manual_reason': 'TJ_NOT_FOUND',
          },
        ),
      );
      final sent = <String>[];
      final transport = FakeTransport((r) async {
        sent.add(r.path);
        if (r.mutation.entity == LocalEntity.song) {
          return MutationResponse(
            201,
            jsonEncode({
              'created': true,
              'canonical_song_id': songId,
              'song': song,
            }),
          );
        }
        if (r.method == 'PATCH') {
          return MutationResponse(
            200,
            jsonEncode({
              ...recording,
              'revision': 2,
              'note': 'new',
              'tier': null,
              'tag_ids': <String>[],
              'tags': <Map<String, Object?>>[],
            }),
          );
        }
        return MutationResponse(201, jsonEncode(recording));
      });
      expect(await repo.dispatch(transport: transport, session: session), 2);
      expect(sent, ['/v1/songs', '/v1/recordings']);
      await repo.save(
        repo.preparePatch(
          entity: LocalEntity.recording,
          entityId: recordingId,
          baseRevision: 1,
          draft: {...recording, 'note': 'new'},
          changes: {'note': 'new'},
        ),
      );
      expect(await repo.dispatch(transport: transport, session: session), 1);
      expect(
        (await repo.read(LocalEntity.recording, recordingId))!.revision,
        2,
      );
    },
  );

  test(
    'redirect is retained without following or forwarding credentials',
    () async {
      await createTag(10);
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final listener = server.listen((r) async {
        requests++;
        r.response.statusCode = 302;
        r.response.headers.set(
          'Location',
          'http://127.0.0.1:${server.port}/forward',
        );
        await r.response.close();
      });
      try {
        final transport = HttpMutationTransport(
          Uri.parse('http://127.0.0.1:${server.port}'),
          allowLocalHttp: true,
        );
        expect(
          await HttpOverrides.runWithHttpOverrides(
            () => repo.dispatch(transport: transport, session: session),
            RealHttpOverrides(),
          ),
          0,
        );
        expect(requests, 1);
        expect((await repo.pending()).single.state, 'RETRY');
      } finally {
        await server.close(force: true);
        await listener.cancel();
      }
    },
  );

  test(
    'missing condition snapshot cannot ACK a selected recording condition',
    () async {
      final target = id(30);
      final draft = {
        'metadata_state': 'DRAFT',
        'recorded_at': time,
        'timezone_id': 'UTC',
        'timezone_offset_minutes': 0,
        'condition_code': 'GOOD',
      };
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.recording,
          entityId: target,
          draft: draft,
          changes: draft,
        ),
      );
      final incomplete = {
        'id': target,
        'metadata_state': 'DRAFT',
        'song_id': null,
        'title_snapshot': null,
        'artist_snapshot': null,
        'version_code': 'NORMAL',
        'key_mode': null,
        'key_shift': null,
        'note': '',
        'recorded_at': time,
        'timezone_id': 'UTC',
        'timezone_offset_minutes': 0,
        'origin_device_id': id(2),
        'revision': 1,
        'link_revision': 1,
        'updated_at': time,
        'lifecycle_state': 'ACTIVE',
      };
      expect(
        await repo.dispatch(
          transport: FakeTransport(
            (r) async => MutationResponse(201, jsonEncode(incomplete)),
          ),
          session: session,
        ),
        0,
      );
      expect((await repo.pending()).single.state, 'RETRY');
      expect(
        jsonDecode(
          (await repo.read(LocalEntity.recording, target))!.localJson!,
        )['condition_code'],
        'GOOD',
      );
    },
  );

  test(
    'missing representative keys cannot ACK or erase a song PATCH',
    () async {
      final target = id(31);
      final song = {
        'id': target,
        'revision': 1,
        'updated_at': time,
        'source_type': 'MANUAL',
        'tj_number': null,
        'title': 'song',
        'artist': 'artist',
        'version_code': 'NORMAL',
        'tier': null,
        'note': '',
        'lifecycle_state': 'ACTIVE',
        'representative_key_mode': null,
        'representative_key_shift': null,
        'representative_recording_id': null,
      };
      final db = await raw();
      await db.customStatement(
        'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,local_payload,updated_at) VALUES(?,?,?,1,?,?,1)',
        [owner, 'SONG', target, jsonEncode(song), jsonEncode(song)],
      );
      await db.close();
      await repo.save(
        repo.preparePatch(
          entity: LocalEntity.song,
          entityId: target,
          baseRevision: 1,
          draft: {
            ...song,
            'representative_key_mode': 'MALE',
            'representative_key_shift': 5,
          },
          changes: {
            'representative_key_mode': 'MALE',
            'representative_key_shift': 5,
          },
        ),
      );
      final incomplete = {...song, 'revision': 2}
        ..remove('representative_key_mode')
        ..remove('representative_key_shift');
      expect(
        await repo.dispatch(
          transport: FakeTransport(
            (r) async => MutationResponse(200, jsonEncode(incomplete)),
          ),
          session: session,
        ),
        0,
      );
      expect((await repo.pending()).single.state, 'RETRY');
      expect(
        jsonDecode(
          (await repo.read(LocalEntity.song, target))!.localJson!,
        )['representative_key_shift'],
        5,
      );
    },
  );

  test(
    '201 created false never replaces local song with an existing server copy',
    () async {
      final target = id(32);
      await repo.save(
        repo.prepareCreate(
          entity: LocalEntity.song,
          entityId: target,
          draft: {'title': 'local'},
          changes: {
            'source_type': 'MANUAL',
            'title': 'local',
            'artist': 'artist',
            'manual_reason': 'TJ_NOT_FOUND',
          },
        ),
      );
      final song = {
        'id': target,
        'revision': 1,
        'updated_at': time,
        'source_type': 'MANUAL',
        'tj_number': null,
        'title': 'server',
        'artist': 'artist',
        'version_code': 'NORMAL',
        'tier': null,
        'note': '',
        'lifecycle_state': 'ACTIVE',
        'representative_key_mode': null,
        'representative_key_shift': null,
        'representative_recording_id': null,
      };
      expect(
        await repo.dispatch(
          transport: FakeTransport(
            (r) async => MutationResponse(
              201,
              jsonEncode({
                'created': false,
                'canonical_song_id': target,
                'song': song,
              }),
            ),
          ),
          session: session,
        ),
        0,
      );
      expect((await repo.pending()).single.state, 'RETRY');
      expect(
        jsonDecode(
          (await repo.read(LocalEntity.song, target))!.localJson!,
        )['title'],
        'local',
      );
    },
  );

  for (final entity in [
    LocalEntity.tag,
    LocalEntity.song,
    LocalEntity.recording,
  ]) {
    test(
      '${entity.code} PATCH conflict preserves a server revision below the local baseline',
      () async {
        final target = id(60);
        final Map<String, Object?> current = switch (entity) {
          LocalEntity.tag => tag(target, name: 'remote', revision: 4),
          LocalEntity.song => {
            'id': target,
            'revision': 4,
            'updated_at': time,
            'source_type': 'MANUAL',
            'tj_number': null,
            'title': 'song',
            'artist': 'artist',
            'version_code': 'NORMAL',
            'tier': null,
            'note': 'remote',
            'lifecycle_state': 'ACTIVE',
            'representative_key_mode': null,
            'representative_key_shift': null,
            'representative_recording_id': null,
          },
          _ => {
            'id': target,
            'metadata_state': 'DRAFT',
            'song_id': null,
            'title_snapshot': null,
            'artist_snapshot': null,
            'version_code': 'NORMAL',
            'key_mode': null,
            'key_shift': null,
            'note': 'remote',
            'recorded_at': time,
            'timezone_id': 'UTC',
            'timezone_offset_minutes': 0,
            'origin_device_id': id(2),
            'revision': 4,
            'link_revision': 1,
            'updated_at': time,
            'lifecycle_state': 'ACTIVE',
            'condition_code': null,
            'condition_name_snapshot': null,
            'tier': null,
            'tag_ids': <String>[],
            'tags': <Map<String, Object?>>[],
          },
        };
        final wireFields = jsonDecode(
          await File('../../fixtures/contracts/metadata-response-fields.json')
              .readAsString(),
        ) as Map<String, dynamic>;
        expect(current.keys, unorderedEquals(wireFields[entity.code] as List));
        final base = {...current, 'revision': 5};
        final db = await raw();
        await db.customStatement(
          'INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,local_payload,updated_at) VALUES(?,?,?,5,?,?,1)',
          [owner, entity.code, target, jsonEncode(base), jsonEncode(base)],
        );
        await db.close();
        final field = entity == LocalEntity.tag ? 'name' : 'note';
        await repo.save(
          repo.preparePatch(
            entity: entity,
            entityId: target,
            baseRevision: 5,
            draft: {...base, field: 'local'},
            changes: {field: 'local'},
          ),
        );
        final response = {
          'error': {
            'code': 'REVISION_CONFLICT',
            'message': 'not persisted',
            'details': {'current_revision': 4, 'current': current},
          },
        };
        expect(
          await repo.dispatch(
            transport: FakeTransport(
              (r) async => MutationResponse(409, jsonEncode(response)),
            ),
            session: session,
          ),
          0,
        );
        final pending = (await repo.pending()).single;
        expect(pending.state, 'CONFLICT');
        expect(jsonDecode(pending.serverResponse!)['current'][field], 'remote');
        expect(pending.serverResponse, isNot(contains('not persisted')));
        final copy = (await repo.read(entity, target))!;
        expect(jsonDecode(copy.localJson!)[field], 'local');
        expect(copy.revision, 5);
      },
    );
  }

  test('two senders claim once and ACK retains a later local edit', () async {
    final edit = await createTag(10);
    final started = Completer<void>();
    final response = Completer<MutationResponse>();
    final transport = FakeTransport((r) {
      started.complete();
      return response.future;
    });
    final first = repo.dispatch(transport: transport, session: session);
    await started.future;
    expect(await repo.dispatch(transport: transport, session: session), 0);
    await repo.save(
      repo.preparePatch(
        entity: LocalEntity.tag,
        entityId: edit.entityId,
        baseRevision: 0,
        draft: {'name': 'later'},
        changes: {'name': 'later'},
      ),
    );
    response.complete(MutationResponse(201, jsonEncode(tag(edit.entityId))));
    expect(await first, 1);
    expect(transport.calls, 1);
    final copy = (await repo.read(LocalEntity.tag, edit.entityId))!;
    expect(jsonDecode(copy.localJson!)['name'], 'later');
    expect(copy.revision, 1);
    expect((await repo.pending()).single.baseRevision, 0);
  });

  test(
    'late account A response cannot affect B or a reopened A lease',
    () async {
      final edit = await createTag(10);
      final started = Completer<void>();
      final response = Completer<MutationResponse>();
      final sending = repo.dispatch(
        transport: FakeTransport((r) {
          started.complete();
          return response.future;
        }),
        session: session,
      );
      final assertion = expectLater(sending, throwsStateError);
      await started.future;
      final other = await manager.openAccount(id(3));
      expect(await other.pendingMutations(), isEmpty);
      final reopened = await manager.openAccount(owner);
      response.complete(MutationResponse(201, jsonEncode(tag(edit.entityId))));
      await assertion;
      expect((await reopened.pendingMutations()).single.state, 'RETRY');
      expect(
        (await reopened.readMetadata(LocalEntity.tag, edit.entityId))!.revision,
        0,
      );
    },
  );

  test(
    'HTTP failure waits only its dependency while unrelated tag proceeds',
    () async {
      final a = await createTag(10), b = await createTag(11);
      final transport = FakeTransport(
        (r) async => r.mutation.entityId == a.entityId
            ? const MutationResponse(503, 'private proxy text')
            : MutationResponse(201, jsonEncode(tag(b.entityId))),
      );
      expect(await repo.dispatch(transport: transport, session: session), 1);
      final pending = (await repo.pending()).single;
      expect(pending.state, 'RETRY');
      expect(pending.opId, a.opId);
      expect(await store.recoveryData(), isNot(contains('private proxy text')));
      expect(await repo.dispatch(transport: transport, session: session), 0);
      expect(transport.calls, 2);
    },
  );

  test(
    'only typed network failures become retryable transport failures',
    () async {
      await createTag(10);
      final transport = FakeTransport(
        (_) async => throw const MutationNetworkFailure(),
      );
      expect(await repo.dispatch(transport: transport, session: session), 0);
      final pending = (await repo.pending()).single;
      expect(pending.state, 'RETRY');
      expect(pending.serverResponse, contains('NETWORK_UNAVAILABLE'));
    },
  );

  test(
    'programming failures propagate without mislabeling network failure',
    () async {
      await createTag(10);
      final transport = FakeTransport(
        (_) async => throw StateError('injected'),
      );
      await expectLater(
        repo.dispatch(transport: transport, session: session),
        throwsStateError,
      );
      final pending = (await repo.pending()).single;
      expect(pending.state, 'SENDING');
      expect(pending.serverResponse, isNull);
    },
  );

  test(
    'authentication rejection stops this dispatch without consuming other work',
    () async {
      await createTag(10);
      await createTag(11);
      final transport = FakeTransport(
        (_) async => const MutationResponse(401, '{}'),
      );
      expect(await repo.dispatch(transport: transport, session: session), 0);
      expect(transport.calls, 1);
      expect((await repo.pending()).map((m) => m.state), ['RETRY', 'PENDING']);
    },
  );

  test(
    'partial success cannot ACK and wrong-account credentials never send',
    () async {
      await createTag(10);
      final transport = FakeTransport(
        (r) async => MutationResponse(
          201,
          jsonEncode({'id': r.mutation.entityId, 'revision': 1}),
        ),
      );
      await expectLater(
        repo.dispatch(transport: transport, session: () async => auth(id(3))),
        throwsStateError,
      );
      expect(transport.calls, 0);
      expect((await repo.pending()).single.attemptCount, 0);
      expect(await repo.dispatch(transport: transport, session: session), 0);
      expect((await repo.pending()).single.state, 'RETRY');
    },
  );

  test(
    'ACK failure rolls back metadata and leaves immutable request for recovery',
    () async {
      final edit = await createTag(10);
      final db = await raw();
      await db.customStatement(
        "CREATE TRIGGER reject_ack BEFORE UPDATE ON local_mutations WHEN NEW.queue_state='ACKED' BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      await db.close();
      final transport = FakeTransport(
        (r) async => MutationResponse(201, jsonEncode(tag(edit.entityId))),
      );
      await expectLater(
        repo.dispatch(transport: transport, session: session),
        throwsA(anything),
      );
      expect((await repo.read(LocalEntity.tag, edit.entityId))!.revision, 0);
      expect((await repo.pending()).single.state, 'SENDING');
      final reopened = await raw();
      expect(
        await reopened
            .customSelect('SELECT COUNT(*) AS n FROM mutation_wire_requests')
            .getSingle()
            .then((r) => r.read<int>('n')),
        1,
      );
      await expectLater(
        reopened.customStatement(
          "UPDATE mutation_wire_requests SET relative_path='/v1/songs'",
        ),
        throwsA(anything),
      );
      await reopened.close();
    },
  );
}
