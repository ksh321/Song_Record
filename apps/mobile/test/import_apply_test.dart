import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  final owner = id(1), job = id(90), resource = id(2);
  final bytes = utf8.encode('owned synthetic import bytes');
  final spec = <String, dynamic>{
    'sha256': sha256.convert(bytes).toString(),
    'size_bytes': bytes.length,
    'duration_ms': 1000,
    'codec': 'AAC_LC',
    'sample_rate': 48000,
    'channels': 1,
    'capture_integrity': 'VALIDATED',
  };
  AccountStoreManager createManager() => AccountStoreManager(
    environment: AppEnvironment.dev,
    directory: () async => root,
    temporaryDirectory: () async => root,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('import-apply-journal-');
    manager = createManager();
    store = await manager.openAccount(owner);
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });
  Map<String, dynamic> command({bool audio = false}) {
    final payload = <String, dynamic>{
      'id': resource,
      if (audio) 'metadata_state': 'DRAFT',
      if (!audio) 'source_type': 'MANUAL',
      'title': 'draft',
    };
    if (audio) payload.remove('title');
    return {
      'resource_id': resource,
      'file': audio ? spec : null,
      'edits': [
        {
          'entity': audio ? 'RECORDING' : 'SONG',
          'operation': 'CREATE',
          'id': resource,
          'op_id': id(5),
          'base_revision': 0,
          'draft': {...payload, 'user_id': owner},
          'changes': payload,
        },
      ],
    };
  }

  Future<void> prepare({bool audio = false}) async {
    await store.prepareImportApply(
      jobId: job,
      manifestHash: 'a' * 64,
      items: [command(audio: audio)],
    );
    if (audio) {
      await (await store.privateExportFile(
        job,
        'audio/$resource.m4a',
      )).writeAsBytes(bytes, flush: true);
    }
  }

  Future<void> reopen() async {
    await manager.logout();
    manager = createManager();
    store = await manager.openAccount(owner);
  }

  test(
    'commit then process interruption resumes without another mutation',
    () async {
      await prepare();
      await expectLater(
        store.applyImportNext(
          job,
          () {},
          faultProbe: (phase) async {
            if (phase == 'ITEM_COMMITTED') throw StateError('simulated stop');
          },
        ),
        throwsStateError,
      );
      await reopen();
      expect(await store.applyImportNext(job, () {}), false);
      await prepare();
      expect(await store.applyImportNext(job, () {}), false);
      expect((await store.pendingMutations()).length, 1);
      expect((await store.importApplyResults(job)).single['status'], 'APPLIED');
      expect(await store.pendingImportJobs(), isEmpty);
    },
  );
  test('same job cannot be reused for another plan or manifest', () async {
    await prepare();
    await expectLater(
      store.prepareImportApply(
        jobId: job,
        manifestHash: 'b' * 64,
        items: [command()],
      ),
      throwsStateError,
    );
    await expectLater(
      store.prepareImportApply(jobId: job, manifestHash: 'a' * 64, items: []),
      throwsStateError,
    );
  });
  test('file verified before interruption is reused after reopening', () async {
    await prepare(audio: true);
    await expectLater(
      store.applyImportNext(
        job,
        () {},
        faultProbe: (phase) async {
          if (phase == 'FILE_VERIFIED') throw StateError('simulated stop');
        },
      ),
      throwsStateError,
    );
    expect(await store.pendingMutations(), isEmpty);
    await reopen();
    expect(await store.applyImportNext(job, () {}), true);
    expect(await store.applyImportNext(job, () {}), false);
    expect((await store.pendingMutations()).length, 1);
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    expect(
      await (await paths.checkedFile(paths.audioPath(resource))).readAsBytes(),
      bytes,
    );
  });
  test('different existing file is preserved with no metadata apply', () async {
    await prepare(audio: true);
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    final file = await paths.checkedFile(paths.audioPath(resource));
    await file.writeAsString('existing unrelated original');
    await expectLater(store.applyImportNext(job, () {}), throwsStateError);
    expect(await file.readAsString(), 'existing unrelated original');
    expect(await store.readMetadata(LocalEntity.recording, resource), isNull);
    expect((await store.importApplyResults(job)).single['status'], 'PENDING');
  });
  test('changed staged bytes fail hash verification before persistent file creation', () async {
    await prepare(audio: true);
    await (await store.privateExportFile(
      job,
      'audio/$resource.m4a',
    )).writeAsBytes(List.filled(bytes.length, 0));
    await expectLater(store.applyImportNext(job, () {}), throwsFormatException);
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    expect(
      await (await paths.checkedFile(paths.audioPath(resource))).exists(),
      false,
    );
    expect(await store.pendingMutations(), isEmpty);
  });
  test('account or consent revocation prevents apply', () async {
    await prepare();
    await expectLater(
      store.applyImportNext(job, () => throw StateError('consent expired')),
      throwsStateError,
    );
    expect(await store.pendingMutations(), isEmpty);
    final old = store;
    await manager.openAccount(id(99));
    await expectLater(old.applyImportNext(job, () {}), throwsStateError);
  });
  test(
    'metadata edits and item completion are atomic on a changed baseline',
    () async {
      final item = command();
      (item['edits'] as List).add({
        'entity': 'SONG',
        'operation': 'PATCH',
        'id': resource,
        'op_id': id(6),
        'base_revision': 2,
        'draft': {'id': resource, 'note': 'incoming'},
        'changes': {'base_revision': 2, 'note': 'incoming'},
      });
      await store.prepareImportApply(
        jobId: job,
        manifestHash: 'a' * 64,
        items: [item],
      );
      await expectLater(store.applyImportNext(job, () {}), throwsStateError);
      expect(await store.readMetadata(LocalEntity.song, resource), isNull);
      expect(await store.pendingMutations(), isEmpty);
      expect((await store.importApplyResults(job)).single['status'], 'PENDING');
    },
  );
  test('destructive queued operation in backup is never replayed', () async {
    final item = command();
    (item['edits'] as List).single['operation'] = 'PURGE';
    await expectLater(
      store.prepareImportApply(
        jobId: job,
        manifestHash: 'a' * 64,
        items: [item],
      ),
      throwsFormatException,
    );
    expect(await store.pendingImportJobs(), isEmpty);
  });
}
