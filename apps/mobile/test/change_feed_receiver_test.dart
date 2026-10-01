import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'change_payload_validation_test.dart' show songChange;
import 'snapshot_playlist_item_projection_test.dart'
    show playlistSource, playlistItemSource, playlistParentId, playlistItemId;
import 'support/business_snapshot_fixture.dart';

class FeedTransport implements ChangeFeedTransport {
  late Future<ChangeFeedResponse> Function(ChangeFeedRequest) respond;
  int calls = 0;
  @override
  Future<ChangeFeedResponse> send(
    ChangeFeedRequest request,
    AuthSession session,
    void Function() fence,
  ) {
    fence();
    calls++;
    return respond(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = '11111111-1111-4111-8111-111111111111',
      token = '22222222-2222-4222-8222-222222222222',
      id = '33333333-3333-4333-8333-333333333333';
  final session = AuthSession(
    userId: owner,
    deviceId: owner,
    accessToken: 'synthetic',
    refreshToken: 'unused',
    accessExpiresAt: DateTime.utc(2030),
    refreshExpiresAt: DateTime.utc(2030),
  );
  late Directory dir;
  late AccountStoreManager manager;
  late AccountStore store;
  late FeedTransport transport;
  late ChangeFeedReceiver receiver;
  bool current = true;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sr-feed-receiver-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => dir,
      temporaryDirectory: () async => dir,
      clock: () => DateTime.utc(2026, 9, 30),
    );
    store = await manager.openAccount(owner);
    current = true;
    transport = FeedTransport();
    receiver = ChangeFeedReceiver(
      store: store,
      transport: transport,
      isSessionCurrent: (value) => current && identical(value, session),
    );
  });
  tearDown(() async {
    await manager.logout();
    expect(
      dir.path.split(Platform.pathSeparator).last,
      startsWith('sr-feed-receiver-'),
    );
    await dir.delete(recursive: true);
  });
  Future<void> baseline() async {
    final fixture = businessSnapshotFixture();
    await store.beginSnapshotDownload(token, jsonEncode(fixture['manifest']));
    for (final page in fixture['pages'] as List) {
      await store.appendSnapshotPage(
        token,
        page['entity'] as String,
        0,
        jsonEncode(page),
      );
    }
    await store.verifySnapshotDownload(token);
    await store.applySnapshotDownload(token);
  }

  ChangeFeedResponse response({int after = 7, bool empty = false}) =>
      ChangeFeedResponse(
        200,
        jsonEncode({
          'after_seq': after,
          'next_seq': empty ? after : after + 1,
          'head_seq': empty ? after : after + 1,
          'has_more': false,
          'changes': empty
              ? <Map<String, Object?>>[]
              : [
                  {
                    'change_seq': after + 1,
                    'entity_type': 'SONG',
                    'entity_id': id,
                    'revision': 2,
                    'operation': 'UPSERT',
                    'payload': songChange(id, 2),
                  },
                ],
        }),
      );
  test(
    'requires applied baseline without sending and reads atomic position',
    () async {
      expect(await store.readChangeFeedPosition(), isNull);
      expect(await receiver.step(session), ChangeFeedStep.needsInitialSnapshot);
      expect(transport.calls, 0);
      await baseline();
      final p = (await store.readChangeFeedPosition())!;
      expect(p.cursor, 7);
      expect(p.snapshotToken, token);
      expect(p.toString(), isNot(contains(token)));
    },
  );
  test('one successful page commits cursor, persists on reopen and has no automatic followup', () async {
    await baseline();
    transport.respond = (request) async {
      expect(request.after, 7);
      return response();
    };
    expect(await receiver.step(session), ChangeFeedStep.caughtUp);
    expect(await store.readCursor(), 8);
    expect(transport.calls, 1);
    await manager.logout();
    store = await manager.openAccount(owner);
    expect((await store.readChangeFeedPosition())!.cursor, 8);
  });
  for (final invalid in [false, true]) {
    test(
      'playlist aggregate receiver persists atomically with invalid tail=$invalid',
      () async {
        await baseline();
        final item = playlistItemSource();
        transport.respond = (request) async {
          expect(request.after, 7);
          return ChangeFeedResponse(
            200,
            jsonEncode({
              'after_seq': 7,
              'next_seq': 8,
              'head_seq': 8,
              'has_more': false,
              'changes': [
                {
                  'change_seq': 8,
                  'entity_type': 'PLAYLIST',
                  'entity_id': playlistParentId,
                  'revision': 8,
                  'operation': 'UPSERT',
                  'payload': {
                    'playlist': playlistSource(),
                    'items': [item, if (invalid) item],
                  },
                },
              ],
            }),
          );
        };
        if (invalid) {
          await expectLater(receiver.step(session), throwsFormatException);
        } else {
          expect(await receiver.step(session), ChangeFeedStep.caughtUp);
        }
        expect(transport.calls, 1);
        await manager.logout();
        store = await manager.openAccount(owner);
        expect(await store.readCursor(), invalid ? 7 : 8);
        final parent = await store.readMetadata(
          LocalEntity.playlist,
          playlistParentId,
        );
        final savedItem = await store.readMetadata(
          LocalEntity.playlistItem,
          playlistItemId,
        );
        if (invalid) {
          expect(parent, isNull);
          expect(savedItem, isNull);
        } else {
          expect(parent!.revision, 8);
          expect(savedItem!.revision, 8);
          expect(
            jsonDecode(savedItem.serverJson!)['playlist_id'],
            playlistParentId,
          );
          expect(jsonDecode(savedItem.serverJson!)['entry_key'], 'tj:123');
        }
      },
    );
  }
  test('more pages reports progress without sending a second request automatically', () async {
    await baseline();
    transport.respond = (_) async => ChangeFeedResponse(
      200,
      jsonEncode({
        'after_seq': 7,
        'next_seq': 57,
        'head_seq': 58,
        'has_more': true,
        'changes': [
          for (var index = 0; index < 50; index++)
            {
              'change_seq': 8 + index,
              'entity_type': 'SONG',
              'entity_id': id,
              'revision': 2 + index,
              'operation': 'UPSERT',
              'payload': songChange(id, 2 + index),
            },
        ],
      }),
    );
    expect(await receiver.step(session), ChangeFeedStep.progressed);
    expect(transport.calls, 1);
    expect(await store.readCursor(), 57);
  });
  test('concurrent calls share one delayed request', () async {
    await baseline();
    final gate = Completer<ChangeFeedResponse>(), sent = Completer<void>();
    transport.respond = (_) {
      sent.complete();
      return gate.future;
    };
    final first = receiver.step(session), second = receiver.step(session);
    expect(identical(first, second), isTrue);
    await sent.future;
    gate.complete(response());
    expect(await first, ChangeFeedStep.caughtUp);
    await second;
    expect(transport.calls, 1);
  });
  for (final status in [401, 403]) {
    test(
      'delayed $status latches concurrent and subsequent calls until explicit reauthentication',
      () async {
        await baseline();
        final gate = Completer<ChangeFeedResponse>(), sent = Completer<void>();
        transport.respond = (_) {
          sent.complete();
          return gate.future;
        };
        final first = receiver.step(session);
        await sent.future;
        final concurrent = receiver.step(session);
        gate.complete(ChangeFeedResponse(status, 'untrusted body'));
        expect(await first, ChangeFeedStep.authenticationRequired);
        expect(await concurrent, ChangeFeedStep.authenticationRequired);
        expect(
          await receiver.step(session),
          ChangeFeedStep.authenticationRequired,
        );
        expect(transport.calls, 1);
        expect(await store.readCursor(), 7);
        receiver.resumeAfterAuthentication();
        transport.respond = (_) async => response(empty: true);
        expect(await receiver.step(session), ChangeFeedStep.caughtUp);
        expect(transport.calls, 2);
      },
    );
  }
  test(
    'authentication headers followed by body failure still block sending',
    () async {
      await baseline();
      transport.respond = (_) async =>
          throw const ChangeFeedTransportFailure(403);
      expect(
        await receiver.step(session),
        ChangeFeedStep.authenticationRequired,
      );
      expect(
        await receiver.step(session),
        ChangeFeedStep.authenticationRequired,
      );
      expect(transport.calls, 1);
    },
  );
  test('cursor expiry reports resync need without changing snapshots, queue or cursor', () async {
    await baseline();
    final before = (jsonDecode(await store.recoveryData()) as Map)['tables'];
    transport.respond = (_) async =>
        const ChangeFeedResponse(409, '{"error":{"code":"CURSOR_EXPIRED"}}');
    expect(await receiver.step(session), ChangeFeedStep.cursorExpired);
    expect((jsonDecode(await store.recoveryData()) as Map)['tables'], before);
  });
  test(
    'expired cursor schedules durable refresh without advancing old cursor',
    () async {
      await baseline();
      receiver = ChangeFeedReceiver(
        store: store,
        transport: transport,
        isSessionCurrent: (_) => current,
        newOperationId: () => id,
      );
      transport.respond = (_) async =>
          const ChangeFeedResponse(409, '{"error":{"code":"CURSOR_EXPIRED"}}');
      expect(await receiver.step(session), ChangeFeedStep.needsInitialSnapshot);
      expect(await store.readCursor(), 7);
      expect(await store.hasCompleteBaseline(), isFalse);
      expect(jsonDecode((await store.readSnapshotResume())!)['op_id'], id);
      expect(await receiver.step(session), ChangeFeedStep.needsInitialSnapshot);
      expect(transport.calls, 1);
    },
  );
  test(
    'retryable transport/server failure and invalid page never advance cursor',
    () async {
      await baseline();
      for (final status in [429, 503]) {
        transport.respond = (_) async => ChangeFeedResponse(status, 'bad');
        expect(await receiver.step(session), ChangeFeedStep.retryLater);
      }
      transport.respond = (_) async =>
          throw const ChangeFeedTransportFailure(null);
      expect(await receiver.step(session), ChangeFeedStep.retryLater);
      transport.respond = (_) async => response(after: 9);
      await expectLater(receiver.step(session), throwsFormatException);
      expect(await store.readCursor(), 7);
    },
  );
  test(
    'session replacement while awaiting response prevents application',
    () async {
      await baseline();
      final gate = Completer<ChangeFeedResponse>(), sent = Completer<void>();
      transport.respond = (_) {
        sent.complete();
        return gate.future;
      };
      final failed = expectLater(receiver.step(session), throwsStateError);
      await sent.future;
      current = false;
      gate.complete(response());
      await failed;
      expect(await store.readCursor(), 7);
      expect(transport.calls, 1);
    },
  );
}
