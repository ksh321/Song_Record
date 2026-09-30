import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/snapshot_receiver.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const token = '22222222-2222-4222-8222-222222222222';
const op = '33333333-3333-4333-8333-333333333333';
final session = AuthSession(
  userId: owner,
  deviceId: owner,
  accessToken: 'synthetic',
  refreshToken: 'unused',
  accessExpiresAt: DateTime.utc(2030),
  refreshExpiresAt: DateTime.utc(2030),
);

class FakeTransport implements SnapshotTransport {
  late Future<SnapshotHttpResponse> Function(SnapshotHttpRequest) respond;
  final requests = <SnapshotHttpRequest>[];
  @override
  Future<SnapshotHttpResponse> send(
    SnapshotHttpRequest request,
    AuthSession session,
    void Function() fence,
  ) {
    fence();
    requests.add(request);
    return respond(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AccountStoreManager manager;
  late AccountStore store;
  late FakeTransport transport;
  late Map<String, dynamic> fixture;
  late DateTime now;
  SnapshotReceiver receiver() => SnapshotReceiver(
    store: store,
    transport: transport,
    newOperationId: () => op,
    clock: () => now,
  );
  final receipt = SnapshotHttpResponse(
    202,
    jsonEncode({
      'operation_id': op,
      'snapshot_token': token,
      'status': 'BUILDING',
      'status_url': '/v1/sync/snapshots/$token',
    }),
  );
  setUp(() async {
    now = DateTime.utc(2026, 9, 30);
    dir = await Directory.systemTemp.createTemp('sr-receiver-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => dir,
      temporaryDirectory: () async => dir,
      clock: () => now,
    );
    store = await manager.openAccount(owner);
    transport = FakeTransport();
    fixture = jsonDecode(
      File('../../fixtures/contracts/snapshot-wire.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });
  tearDown(() async {
    await manager.logout();
    expect(
      dir.path.split(Platform.pathSeparator).last,
      startsWith('sr-receiver-'),
    );
    await dir.delete(recursive: true);
  });

  test(
    'lost creation response persists same operation across restart',
    () async {
      transport.respond = (_) async {
        final saved = jsonDecode((await store.readSnapshotResume())!);
        expect(saved['op_id'], op);
        throw const SnapshotTransportFailure(null);
      };
      expect(await receiver().step(session), SnapshotStep.retryLater);
      await manager.logout();
      store = await manager.openAccount(owner);
      transport.respond = (_) async => receipt;
      expect(await receiver().step(session), SnapshotStep.progressed);
      expect(transport.requests.map((r) => r.operationId), [op, op]);
    },
  );

  for (final status in [401, 403]) {
    test(
      'delayed $status and concurrent resume produce only one request',
      () async {
        final gate = Completer<SnapshotHttpResponse>();
        transport.respond = (_) => gate.future;
        final runner = receiver();
        final first = runner.step(session);
        final resumed = runner.step(session);
        gate.complete(SnapshotHttpResponse(status, '{}'));
        expect(await first, SnapshotStep.authenticationRequired);
        expect(await resumed, SnapshotStep.authenticationRequired);
        expect(await runner.step(session), SnapshotStep.authenticationRequired);
        expect(transport.requests, hasLength(1));
        runner.resumeAfterAuthentication();
        transport.respond = (_) async => receipt;
        expect(await runner.step(session), SnapshotStep.progressed);
        expect(transport.requests, hasLength(2));
        expect(transport.requests.last.operationId, op);
      },
    );
  }

  test(
    'manifest and all 19 pages resume and apply verified baseline once',
    () async {
      transport.respond = (request) async {
        if (request.method == 'POST') return receipt;
        final entity = request.query['entity'];
        if (entity == null) {
          return SnapshotHttpResponse(200, jsonEncode(fixture['manifest']));
        }
        return SnapshotHttpResponse(
          200,
          jsonEncode(
            (fixture['pages'] as List).singleWhere(
              (p) => p['entity'] == entity,
            ),
          ),
        );
      };
      var runner = receiver();
      expect(await runner.step(session), SnapshotStep.progressed);
      expect(await runner.step(session), SnapshotStep.progressed);
      for (var i = 0; i < 7; i++) {
        expect(await runner.step(session), SnapshotStep.progressed);
      }
      await manager.logout();
      store = await manager.openAccount(owner);
      runner = receiver();
      for (var i = 7; i < 19; i++) {
        expect(await runner.step(session), SnapshotStep.progressed);
      }
      expect(await runner.step(session), SnapshotStep.complete);
      expect(await store.readCursor(), 7);
      expect(await store.readSnapshotResume(), isNull);
      expect(transport.requests, hasLength(21));
      expect(await runner.step(session), SnapshotStep.complete);
      expect(transport.requests, hasLength(21));
    },
  );

  test('expired server snapshot clears only pending resume without follow-up request', () async {
    transport.respond = (_) async => receipt;
    final runner = receiver();
    await runner.step(session);
    transport.respond = (_) async => const SnapshotHttpResponse(410, '{}');
    expect(await runner.step(session), SnapshotStep.progressed);
    expect(await store.readSnapshotResume(), isNull);
    expect(transport.requests, hasLength(2));
    expect(await store.readCursor(), isNull);
  });

  test('invalid page cursor discards staging and waits before requesting a new snapshot', () async {
    transport.respond = (request) async => request.method == 'POST'
        ? receipt
        : SnapshotHttpResponse(200, jsonEncode(fixture['manifest']));
    final runner = receiver();
    await runner.step(session);
    await runner.step(session);
    transport.respond = (_) async =>
        const SnapshotHttpResponse(400, '{"error":{"code":"INVALID_CURSOR"}}');
    expect(await runner.step(session), SnapshotStep.progressed);
    expect(transport.requests, hasLength(3));
    expect(await store.readSnapshotResume(), isNull);
    expect(await store.hasCompleteBaseline(), isFalse);
    await expectLater(store.snapshotDownloadState(token), throwsStateError);
  });

  test(
    'late response after logout cannot save a token or send another request',
    () async {
      final gate = Completer<SnapshotHttpResponse>();
      final arrived = Completer<void>();
      transport.respond = (_) {
        arrived.complete();
        return gate.future;
      };
      final runner = receiver();
      final pending = expectLater(runner.step(session), throwsStateError);
      await arrived.future;
      await manager.logout();
      gate.complete(receipt);
      await pending;
      store = await manager.openAccount(owner);
      final saved = jsonDecode((await store.readSnapshotResume())!);
      expect(saved['phase'], 'REQUESTED');
      expect(saved['token'], isNull);
      expect(transport.requests, hasLength(1));
    },
  );
}
