import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/files/local_preservation.dart';

String preservationId(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

final class SyntheticPreservationDownload implements PreservationDownload {
  SyntheticPreservationDownload(this.bytes);
  final Uint8List bytes;
  int count = 0;
  Future<void> Function()? before;
  @override
  Future<Uint8List> download(
    PreservationObject object,
    Future<void> Function() guard,
  ) async {
    count++;
    await before?.call();
    await guard();
    return bytes;
  }
}

Future<List<String>> runPreservationChecks(Directory root) async {
  final manager = AccountStoreManager(
    environment: AppEnvironment.dev,
    directory: () async => root,
    temporaryDirectory: () async => root,
  );
  final owner = preservationId(1),
      id = preservationId(2),
      other = preservationId(3);
  final bytes = Uint8List.fromList(
    utf8.encode('P13-03 synthetic preservation bytes'),
  );
  final object = PreservationObject(
    owner: owner,
    recording: id,
    generation: preservationId(4),
    checksum: sha256.convert(bytes).toString(),
    size: bytes.length,
    revision: 1,
  );
  final download = SyntheticPreservationDownload(bytes);
  final results = <String>[];
  void check(bool pass) {
    if (!pass) throw StateError('Preservation scenario failed');
  }

  try {
    var store = await manager.openAccount(owner);
    var flow = LocalPreservation(store, download);
    await flow.verify(object);
    check(download.count == 1);
    check(
      await store.verifyPreservedAudio(
        owner,
        id,
        object.checksum,
        bytes.length,
      ),
    );
    results.add('파일 없는 기기: 다운로드 후 영속 파일·체크섬 확인');
    await flow.verify(object);
    check(download.count == 1);
    results.add('정상 로컬 사본: 다시 다운로드하지 않고 실제 바이트 확인');
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    final file = await paths.checkedFile(paths.audioPath(id));
    await file.delete();
    await flow.verify(object);
    check(download.count == 2);
    results.add('과거 로컬 기록만 남음: 삭제된 실제 파일을 다시 내려받음');
    final corrupted = Uint8List.fromList(List<int>.filled(bytes.length, 120));
    await file.writeAsBytes(corrupted, flush: true);
    bool blocked = false;
    try {
      await flow.verify(object);
    } catch (_) {
      blocked = true;
    }
    check(blocked);
    check((await file.readAsBytes()).every((v) => v == 120));
    results.add('내용이 다른 기존 원본: 확인 실패·덮어쓰기 없음');
    await file.delete();
    download.before = () async {
      await manager.openAccount(other);
    };
    blocked = false;
    try {
      await flow.verify(object);
    } catch (_) {
      blocked = true;
    }
    check(blocked);
    check(!await file.exists());
    results.add('다운로드 중 계정 전환: 늦은 결과 저장·보존 확인 차단');
    store = await manager.openAccount(other);
    blocked = false;
    try {
      await LocalPreservation(store, download).verify(object);
    } catch (_) {
      blocked = true;
    }
    check(blocked);
    results.add('다른 계정 사본·보고를 현재 계정 보존으로 인정하지 않음');
    return results;
  } finally {
    await manager.logout();
  }
}
