import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/export/export_audio.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_controller.dart';
import 'package:song_record/features/backup/export/export_job.dart';
import 'package:song_record/features/backup/export/export_screen.dart';
import 'package:song_record/features/backup/export/export_zip.dart';

import 'export_audio_test.dart' as fixture;
import 'support/completed_capture_fixture.dart' as capture;

class Destination implements BackupDestination {
  bool saved = true;
  int calls = 0, cancellations = 0;
  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<bool> save(
    ExportZip zip, {
    required String owner,
    required String environment,
    required String jobId,
  }) async {
    calls++;
    expect(await zip.file.exists(), isTrue);
    return saved;
  }
}

void main() {
  late Directory root;
  late Destination destination;
  int freezes = 0, reads = 0;
  Future<File> file(String name) async {
    final target = File('${root.path}/$name');
    await target.parent.create(recursive: true);
    return target;
  }

  ExportController create({
    Future<String?> Function()? latest,
    int space = 100000000,
    Completer<void>? pause,
  }) => ExportController(
    owner: fixture.owner,
    environment: 'dev',
    requireCurrent: () {},
    prepare: () async => 100000000,
    freeze: (online, trash) async {
      freezes++;
      await pause?.future;
      final source = fixture.baseline(
        [fixture.recording(1), fixture.recording(2)],
        online: online,
        trash: trash,
      );
      return ExportBaseline(
        id: source.id,
        owner: source.owner,
        includeTrash: trash,
        manifest: source.manifest,
        createdAt: source.createdAt,
        entries: source.entries,
        local: {
          ...source.local,
          'baseline': [
            {
              'baseline_complete': 0,
              'last_change_seq': null,
              'updated_at': null,
            },
          ],
        },
      );
    },
    createJob: (id) => ExportJob(
      owner: fixture.owner,
      id: id,
      file: file,
      requireCurrent: () {},
    ),
    createCollector: () => ExportAudioCollector(
      requireCurrent: () {},
      state: (_) async => {},
      local: (id) async {
        reads++;
        return id == fixture.id(1) ? capture.bytes : null;
      },
      staged: (_, id) async => (await file('audio/$id.m4a')).readAsBytes(),
      stage: (_, id, hash, size, Uint8List bytes) async {
        await (await file('audio/$id.m4a')).writeAsBytes(bytes);
      },
    ),
    destination: destination,
    availableBytes: () async => space,
    latestJob: latest,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('export-controller-');
    destination = Destination();
    freezes = 0;
    reads = 0;
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'partial offline result and save cancel/retry retain one frozen baseline',
    () async {
      final controller = create();
      destination.saved = false;
      await controller.start(online: false, includeTrash: false);
      expect(controller.phase, BackupPhase.cancelled);
      expect(controller.manifest!.includedAudioCount, 1);
      expect(controller.manifest!.missingAudioCount, 1);
      final hash = controller.artifact!.checksum;
      destination.saved = true;
      await controller.start(online: true, includeTrash: true);
      expect(controller.phase, BackupPhase.completed);
      expect(freezes, 1);
      expect(destination.calls, 2);
      expect(reads, 2);
      expect(controller.artifact!.checksum, hash);
      expect(controller.manifest!.online, isFalse);
      expect(backupResultLabel(controller.manifest!), contains('이 기기 기준'));
      controller.dispose();
    },
  );

  test(
    'cancel checkpoint and restart resume completed file without refetching it',
    () async {
      final controller = create();
      void listener() {
        if (controller.done == 1 && controller.busy) {
          unawaited(controller.cancel());
        }
      }

      controller.addListener(listener);
      await controller.start(online: false, includeTrash: false);
      controller.removeListener(listener);
      expect(controller.phase, BackupPhase.cancelled);
      final resumed = create(latest: () async => fixture.token);
      await resumed.restore();
      expect(resumed.phase, BackupPhase.resumable);
      expect(resumed.manifest!.includedAudioCount, 1);
      final priorReads = reads;
      await resumed.start(online: false, includeTrash: false);
      expect(resumed.phase, BackupPhase.completed);
      expect(reads, priorReads + 1);
      expect(freezes, 1);
      expect(resumed.manifest!.missingAudioCount, 1);
      controller.dispose();
      resumed.dispose();
    },
  );

  test('space failure and baseline cancellation never report completed or call destination', () async {
    final noSpace = create(space: 0);
    await noSpace.start(online: false, includeTrash: false);
    expect(noSpace.phase, BackupPhase.failed);
    expect(noSpace.error, contains('공간'));
    expect(destination.calls, 0);
    expect(reads, 0);
    noSpace.dispose();
    final pause = Completer<void>(), cancelled = create(pause: pause);
    final running = cancelled.start(online: false, includeTrash: false);
    await Future<void>.delayed(Duration.zero);
    await cancelled.cancel();
    pause.complete();
    await running;
    expect(cancelled.phase, BackupPhase.cancelled);
    expect(destination.calls, 0);
    cancelled.dispose();
  });

  test(
    'corrupt restart retains artifact but requires explicit fresh backup',
    () async {
      final controller = create();
      await controller.start(online: false, includeTrash: false);
      final zip = controller.artifact!;
      await (await file('manifest.json')).writeAsString('{}');
      final resumed = create(latest: () async => fixture.token);
      await resumed.restore();
      expect(resumed.phase, BackupPhase.failed);
      expect(resumed.job, isNull);
      expect(await zip.file.exists(), isTrue);
      expect(resumed.error, contains('새 백업'));
      controller.dispose();
      resumed.dispose();
    },
  );

  testWidgets(
    'screen requires privacy acknowledgement and shows actual partial counts and cutoff',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = create();
      await tester.runAsync(
        () => controller.start(online: true, includeTrash: false),
      );
      await tester.pumpWidget(
        MaterialApp(home: ExportScreen(controller: controller)),
      );
      await tester.pump();
      expect(find.text('백업 완료 · 일부 파일 미포함'), findsOneWidget);
      expect(find.textContaining('포함 파일 1개 · 미포함 1개'), findsOneWidget);
      expect(find.textContaining('로컬 기준:'), findsOneWidget);
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '누락을 확인하고 내보내기'),
      );
      expect(start.onPressed, isNull);
      expect(find.textContaining('비암호화 ZIP'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
