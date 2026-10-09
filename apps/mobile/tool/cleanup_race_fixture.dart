import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/files/cleanup_confirmation.dart';
import 'package:song_record/core/files/local_preservation.dart';

import 'local_preservation_fixture.dart';

final class _LostReply implements CleanupTransport {
  @override
  Future<void> confirmLocal(
    CleanupToken token,
    String operation,
    Future<void> Function() guard,
  ) async {
    await guard();
    throw const CleanupNetworkFailure();
  }
}

final class _Status implements CleanupStatusTransport {
  _Status(this.state);
  final String? state;
  @override
  Future<String?> terminal(
    CleanupToken token,
    Future<void> Function() guard,
  ) async {
    await guard();
    return state;
  }
}

Future<List<String>> runCleanupRaceChecks(Directory root) async {
  var now = DateTime.now().toUtc();
  final manager = AccountStoreManager(
    environment: AppEnvironment.dev,
    directory: () async => root,
    temporaryDirectory: () async => root,
    clock: () => now,
  );
  final owner = preservationId(20),
      id = preservationId(21),
      gen = preservationId(22),
      tokenId = preservationId(23);
  final bytes = Uint8List.fromList(
    utf8.encode('P13-10 synthetic last local copy'),
  );
  final object = PreservationObject(
    owner: owner,
    recording: id,
    generation: gen,
    checksum: sha256.convert(bytes).toString(),
    size: bytes.length,
    revision: 3,
  );
  final token = CleanupToken(
    tokenId,
    object,
    now.add(const Duration(minutes: 15)),
  );
  void check(bool value) {
    if (!value) throw StateError('Cleanup race scenario failed');
  }

  Future<void> blocked(Future<void> Function() action) async {
    bool failed = false;
    try {
      await action();
    } catch (_) {
      failed = true;
    }
    check(failed);
  }

  try {
    var store = await manager.openAccount(owner);
    var flow = LocalCleanupCoordinator(
      store,
      LocalPreservation(store, SyntheticPreservationDownload(bytes)),
      _LostReply(),
    );
    await blocked(() => flow.confirm(token, operation: preservationId(24)));
    check((await store.pendingLocalCleanup()).single['state'] == 'PREPARING');
    await manager.logout();
    now = now.add(const Duration(minutes: 16));
    store = await manager.openAccount(owner);
    check((await store.pendingLocalCleanup()).single['token'] == tokenId);
    await blocked(
      () => store.preserveDownloadedAudio(
        owner,
        id,
        object.checksum,
        bytes.length,
        bytes,
      ),
    );
    await blocked(
      () => store.finishLocalCleanupFence(
        tokenId,
        preservationId(25),
        'SUCCEEDED',
      ),
    );
    await blocked(
      () => store.finishLocalCleanupFence(tokenId, gen, 'DELETING'),
    );
    check(base64Encode(await store.readLocalAudio(id)) == base64Encode(bytes));
    final results = <String>['새 기기 다운로드·확인 응답 손실·재열기·만료·다른 세대가 겹쳐도 마지막 파일 유지'];
    flow = LocalCleanupCoordinator(
      store,
      LocalPreservation(store, SyntheticPreservationDownload(bytes)),
      _LostReply(),
    );
    await flow.resume(_Status(null));
    check((await store.pendingLocalCleanup()).single['state'] == 'PREPARING');
    await flow.resume(_Status('EXPIRED'));
    await flow.resume(_Status('EXPIRED'));
    check((await store.pendingLocalCleanup()).isEmpty);
    check(base64Encode(await store.readLocalAudio(id)) == base64Encode(bytes));
    results.add('서버 상태 미확인에는 펜스 유지·일치한 최종 상태만 해제·원본 파일 보존');
    return results;
  } finally {
    await manager.logout();
  }
}
