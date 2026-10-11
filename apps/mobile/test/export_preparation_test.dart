import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/export/export_preparation.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';

class PreparationRecorder implements RecorderGateway {
  RecorderStatus status = const RecorderStatus.idle();
  RecorderStatus afterStop = completed();
  bool delayed = false, failStop = false;
  int stops = 0;
  final events = StreamController<RecorderStatus>.broadcast();
  static RecorderStatus completed({
    RecorderLocalState state = RecorderLocalState.inputPending,
  }) => RecorderStatus(
    phase: RecorderPhase.completed,
    recordingId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    localState: state,
    sizeBytes: 100,
    durationMs: 1000,
    sha256: 'a' * 64,
  );
  @override
  Future<RecorderStatus> getCurrentStatus() async => status;
  @override
  Stream<RecorderStatus> watchStatus() => events.stream;
  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('stop failed');
    if (!delayed) {
      status = afterStop;
      events.add(status);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PreparationRecorder recorder;
  late ExportPreparation preparation;
  final plan = ExportSpacePlan(
    audioBytes: 100,
    metadataBytes: 100,
    fileCount: 1,
  );
  int preserved = 0, spaceReads = 0;
  bool cancelled = false, current = true;
  setUp(() {
    recorder = PreparationRecorder();
    preserved = spaceReads = 0;
    cancelled = false;
    current = true;
    preparation = ExportPreparation(
      recorder: recorder,
      preserve: (status) async {
        preserved++;
      },
      requireCurrent: () {
        if (!current) throw StateError('account changed');
      },
      availableBytes: () async {
        spaceReads++;
        return plan.requiredBytes;
      },
      stopTimeout: const Duration(milliseconds: 20),
    );
  });
  tearDown(() => recorder.events.close());
  test('idle needs space but never stops or promotes a capture', () async {
    expect(await preparation.prepare(plan), plan.requiredBytes);
    expect(recorder.stops, 0);
    expect(preserved, 0);
    expect(spaceReads, 1);
  });
  test(
    'active recording finishes and persists before checking space',
    () async {
      recorder.status = const RecorderStatus(
        phase: RecorderPhase.recording,
        recordingId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        localState: RecorderLocalState.capturing,
      );
      expect(await preparation.prepare(plan), plan.requiredBytes);
      expect(recorder.stops, 1);
      expect(preserved, 1);
    },
  );
  test(
    'stop failure preserves original state and never starts backup',
    () async {
      recorder.status = const RecorderStatus(
        phase: RecorderPhase.recording,
        recordingId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      );
      recorder.failStop = true;
      await expectLater(preparation.prepare(plan), throwsStateError);
      expect(preserved, 0);
      expect(spaceReads, 0);
      expect(recorder.status.phase, RecorderPhase.recording);
    },
  );
  test('completion timeout never treats capturing M4A as ready', () async {
    recorder.status = const RecorderStatus(
      phase: RecorderPhase.recording,
      recordingId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    recorder.delayed = true;
    await expectLater(
      preparation.prepare(plan),
      throwsA(isA<TimeoutException>()),
    );
    expect(preserved, 0);
    expect(spaceReads, 0);
  });
  test('corrupt or interrupted terminal state cannot be promoted', () async {
    recorder.status = PreparationRecorder.completed(
      state: RecorderLocalState.corrupt,
    );
    await expectLater(preparation.prepare(plan), throwsStateError);
    expect(preserved, 0);
    recorder.status = const RecorderStatus(
      phase: RecorderPhase.error,
      localState: RecorderLocalState.interrupted,
    );
    await expectLater(preparation.prepare(plan), throwsStateError);
    expect(spaceReads, 0);
  });
  test(
    'cancellation and account change occur before any stop or persistence',
    () async {
      cancelled = true;
      await expectLater(
        preparation.prepare(plan, isCancelled: () => cancelled),
        throwsStateError,
      );
      cancelled = false;
      current = false;
      await expectLater(preparation.prepare(plan), throwsStateError);
      expect(recorder.stops, 0);
      expect(spaceReads, 0);
    },
  );
  test('space calculation includes both staging and ZIP with a reserve', () {
    final estimate = ExportSpacePlan(
      audioBytes: 1024,
      metadataBytes: 512,
      fileCount: 2,
    );
    expect(estimate.requiredBytes, greaterThan(2 * 1024 + 2 * 512));
    expect(estimate.fits(estimate.requiredBytes), isTrue);
    expect(estimate.fits(estimate.requiredBytes - 1), isFalse);
    expect(
      () => ExportSpacePlan(audioBytes: -1, metadataBytes: 0, fileCount: 0),
      throwsArgumentError,
    );
    expect(
      () => ExportSpacePlan(
        audioBytes: 0x1fffffffffffff,
        metadataBytes: 0,
        fileCount: 1,
      ),
      throwsArgumentError,
    );
  });
  test('insufficient space fails without clearing any capture', () async {
    final tooLarge = ExportSpacePlan(
      audioBytes: 99999,
      metadataBytes: 100,
      fileCount: 1,
    );
    await expectLater(preparation.prepare(tooLarge), throwsStateError);
    expect(recorder.status.phase, RecorderPhase.idle);
    expect(preserved, 0);
  });
  test(
    'backup status listener cancellation leaves the recorder screen subscribed',
    () async {
      const channel = EventChannel('com.ksh321.songrecord/recorder_events');
      final ready = Completer<MockStreamHandlerEventSink>();
      int listens = 0, cancels = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            channel,
            MockStreamHandler.inline(
              onListen: (_, sink) {
                listens++;
                ready.complete(sink);
              },
              onCancel: (_) {
                cancels++;
              },
            ),
          );
      const gateway = MethodChannelRecorderGateway();
      final screenSeen = <RecorderPhase>[], backupSeen = <RecorderPhase>[];
      final firstEvent = Completer<void>(), finalEvent = Completer<void>();
      final screen = gateway.watchStatus().listen((value) {
        screenSeen.add(value.phase);
        if (value.phase == RecorderPhase.completed) finalEvent.complete();
      });
      final backup = gateway.watchStatus().listen((value) {
        backupSeen.add(value.phase);
        firstEvent.complete();
      });
      final sink = await ready.future;
      sink.success({'phase': 'recording'});
      await firstEvent.future;
      await backup.cancel();
      expect(cancels, 0);
      sink.success({'phase': 'completed'});
      await finalEvent.future;
      expect(screenSeen, [RecorderPhase.recording, RecorderPhase.completed]);
      expect(backupSeen, [RecorderPhase.recording]);
      expect(listens, 1);
      await screen.cancel();
      expect(cancels, 1);
    },
  );
}
