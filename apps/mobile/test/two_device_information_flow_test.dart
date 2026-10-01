import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_receiver.dart';
import 'package:song_record/core/sync/change_feed_transport.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'support/business_snapshot_fixture.dart';

/// These bodies are produced and checked by TwoDeviceInformationFlowTests in
/// Spring. Replay transport is intentional; this is not a physical-device test.
class ContractWrites implements MutationTransport {
  ContractWrites(this.steps);
  final List<Map<String, dynamic>> steps;
  int position = 0;
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    expect(position, lessThan(steps.length));
    final step = steps[position++];
    expect(jsonDecode(request.body), step['request']);
    expect(request.method, step['method']);
    expect(request.path, step['path']);
    return MutationResponse(
      step['status'] as int,
      jsonEncode(step['response']),
    );
  }
}

class ContractReads implements ChangeFeedTransport {
  ContractReads(this.pages);
  final List<dynamic> pages;
  int position = 0;
  @override
  Future<ChangeFeedResponse> send(
    ChangeFeedRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    expect(position, lessThan(pages.length));
    final page = pages[position++] as Map;
    expect(request.after, page['after_seq']);
    return ChangeFeedResponse(200, jsonEncode(page));
  }
}

Future<void> emptyBaseline(AccountStore store) async {
  final fixture = businessSnapshotFixture();
  final manifest = fixture['manifest'] as Map<String, dynamic>;
  manifest['snapshot_cursor'] = 0;
  final counts = manifest['entity_counts'] as Map;
  for (final page in fixture['pages'] as List) {
    page['snapshot_cursor'] = 0;
    if (page['entity'] == 'USER_SYNC_STATE') {
      final entry = (page['entries'] as List).single as Map;
      final payload = entry['payload'] as Map<String, dynamic>;
      payload['last_change_seq'] = 0;
      payload['retained_from_seq'] = 1;
      entry['canonical_payload'] = canonicalJson(payload);
    } else {
      page['entries'] = <Object?>[];
    }
    counts[page['entity']] = (page['entries'] as List).length;
  }
  refreshSnapshotHash(fixture);
  final token = manifest['snapshot_token'] as String;
  await store.beginSnapshotDownload(token, jsonEncode(manifest));
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('two isolated local stores exchange actual server contracts without copying audio', () async {
    final fixture = jsonDecode(
      await File('../../fixtures/contracts/two-device-recording.json')
          .readAsString(),
    ) as Map<String, dynamic>;
    final owner = fixture['owner'] as String,
        id = fixture['recording_id'] as String;
    final root = await Directory.systemTemp.createTemp('sr-two-device-flow-');
    final dirA = Directory('${root.path}/a'),
        dirB = Directory('${root.path}/b');
    AccountStoreManager manager(Directory dir) => AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => dir,
      temporaryDirectory: () async => dir,
      clock: () => DateTime.utc(2026, 9, 30),
    );
    final managerA = manager(dirA), managerB = manager(dirB);
    AuthSession session(String device) => AuthSession(
      userId: owner,
      deviceId: device,
      accessToken: 'synthetic',
      refreshToken: 'unused',
      accessExpiresAt: DateTime.utc(2030),
      refreshExpiresAt: DateTime.utc(2030),
    );
    final authA = session(fixture['device_a'] as String),
        authB = session(fixture['device_b'] as String);
    try {
      final a = await managerA.openAccount(owner);
      var b = await managerB.openAccount(owner);
      await emptyBaseline(a);
      await emptyBaseline(b);
      final repoA = LocalRepository(a);
      final create = Map<String, Object?>.from(fixture['create_request'] as Map)
        ..remove('id');
      final save = Map<String, Object?>.from(fixture['save_request'] as Map)
        ..remove('base_revision');
      await repoA.save(
        repoA.prepareCreate(
          entity: LocalEntity.recording,
          entityId: id,
          draft: create,
          changes: create,
        ),
      );
      await repoA.save(
        repoA.preparePatch(
          entity: LocalEntity.recording,
          entityId: id,
          baseRevision: 0,
          draft: {...create, ...save},
          changes: save,
        ),
      );
      final pathsA = await AccountPaths.create(dirA, owner, AppEnvironment.dev);
      final audioA = await pathsA.checkedFile(pathsA.audioPath(id));
      await audioA.writeAsBytes([1, 3, 5, 7]);
      final senderA = ContractWrites([
        {
          'method': 'POST',
          'path': '/v1/recordings',
          'status': 201,
          'request': fixture['create_request'],
          'response': fixture['create_response'],
        },
        {
          'method': 'PATCH',
          'path': '/v1/recordings/$id',
          'status': 200,
          'request': fixture['save_request'],
          'response': fixture['save_response'],
        },
      ]);
      expect(
        await repoA.dispatch(transport: senderA, session: () async => authA),
        2,
      );
      expect(senderA.position, 2);
      expect(await repoA.pendingWork(), isEmpty);
      final pages = fixture['pages'] as List;
      final readsB = ContractReads(pages.take(2).toList());
      ChangeFeedReceiver receiver(
        AccountStore store,
        ContractReads reads,
        AuthSession auth,
      ) => ChangeFeedReceiver(
        store: store,
        transport: reads,
        isSessionCurrent: (current) => identical(current, auth),
      );
      expect(
        await receiver(b, readsB, authB).step(authB),
        ChangeFeedStep.caughtUp,
      );
      // Resume the second receiver with its own durable cursor after restart.
      await managerB.logout();
      b = await managerB.openAccount(owner);
      expect(
        await receiver(b, readsB, authB).step(authB),
        ChangeFeedStep.caughtUp,
      );
      var received = (await b.readMetadata(LocalEntity.recording, id))!;
      expect(received.revision, 2);
      expect(jsonDecode(received.serverJson!)['metadata_state'], 'SAVED');
      final pathsB = await AccountPaths.create(dirB, owner, AppEnvironment.dev);
      expect(
        await (await pathsB.checkedFile(pathsB.audioPath(id))).exists(),
        isFalse,
      );
      final repoB = LocalRepository(b);
      final tier = Map<String, Object?>.from(fixture['tier_request'] as Map)
        ..remove('base_revision');
      await repoB.save(
        repoB.preparePatch(
          entity: LocalEntity.recording,
          entityId: id,
          baseRevision: 2,
          draft: {
            ...jsonDecode(received.serverJson!) as Map<String, dynamic>,
            ...tier,
          },
          changes: tier,
        ),
      );
      final senderB = ContractWrites([
        {
          'method': 'PATCH',
          'path': '/v1/recordings/$id/tier',
          'status': 200,
          'request': fixture['tier_request'],
          'response': fixture['tier_response'],
        },
      ]);
      expect(
        await repoB.dispatch(transport: senderB, session: () async => authB),
        1,
      );
      final readsA = ContractReads(pages);
      final receiverA = receiver(a, readsA, authA);
      for (var i = 0; i < 3; i++) {
        expect(await receiverA.step(authA), ChangeFeedStep.caughtUp);
      }
      received = (await a.readMetadata(LocalEntity.recording, id))!;
      expect(received.revision, 3);
      expect(jsonDecode(received.serverJson!)['tier'], 'A');
      expect(jsonDecode(received.serverJson!)['note'], 'retained note');
      expect((await a.readChangeFeedPosition())!.cursor, 3);
      expect(await audioA.readAsBytes(), [1, 3, 5, 7]);
      expect(
        await (await pathsB.checkedFile(pathsB.audioPath(id))).exists(),
        isFalse,
      );
    } finally {
      await managerA.logout();
      await managerB.logout();
      expect(
        root.path.split(Platform.pathSeparator).last,
        startsWith('sr-two-device-flow-'),
      );
      await root.delete(recursive: true);
    }
  });
}
