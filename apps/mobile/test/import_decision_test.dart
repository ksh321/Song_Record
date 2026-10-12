import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/import/import_decision.dart';
import 'package:song_record/features/backup/import/import_decision_screen.dart';
import 'package:song_record/features/backup/import/import_validation.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

import 'export_audio_test.dart' as fixture;

ValidatedImport decisionFixture({String? issue, String? issueId}) {
  final source = fixture.baseline([fixture.recording(1), fixture.recording(2)]);
  final baseline = ExportBaseline(
    id: source.id,
    owner: source.owner,
    includeTrash: false,
    manifest: null,
    createdAt: source.createdAt,
    entries: source.entries,
    local: {
      ...source.local,
      'baseline': [
        {'baseline_complete': 0, 'last_change_seq': null, 'updated_at': null},
      ],
    },
  );
  final data = ExportData.fromBaseline(baseline);
  final manifest = ExportManifest.fromBaseline(
    baseline,
    metadataCount: data.metadataCount,
    files: [
      for (final n in [1, 2])
        ExportAudioEntry(
          recordingId: fixture.id(n),
          selected: true,
          included: true,
          missingReason: null,
          sha256: 'a' * 64,
          sizeBytes: 5,
          durationMs: 12000,
        ),
    ],
  );
  return ValidatedImport(
    ImportZipStaging(Directory.systemTemp, const {}),
    manifest,
    ImportData.decode(data.encode(), manifest),
    [if (issue != null) ImportValidationIssue(issue, issueId ?? fixture.id(1))],
  );
}

void main() {
  test(
    'damage blocks whole restore with no automatic partial approval',
    () async {
      final source = decisionFixture(issue: 'AUDIO_HASH_OR_SIZE');
      final controller = ImportDecision(
        validate: (_) => Future.value(source),
        requireCurrent: () {},
      );
      addTearDown(controller.dispose);
      await controller.check();
      expect(controller.phase, ImportDecisionPhase.blocked);
      expect(controller.approval, isNull);
      expect(controller.canApproveWhole, false);
      expect(controller.approveWhole, throwsStateError);
      final consent = controller.approvePartial();
      expect(consent.partial, true);
      expect(consent.fileIds, {fixture.id(2)});
      expect(consent.source.issues.single.code, 'AUDIO_HASH_OR_SIZE');
      controller.requireConsent(consent);
      controller.cancel();
      expect(() => controller.requireConsent(consent), throwsStateError);
    },
  );
  test(
    'normal source waits for explicit whole approval; arrays are immutable',
    () async {
      final controller = ImportDecision(
        validate: (_) => Future.value(decisionFixture()),
        requireCurrent: () {},
      );
      addTearDown(controller.dispose);
      await controller.check();
      expect(controller.approval, isNull);
      final choice = controller.approveWhole();
      expect(choice.partial, false);
      expect(choice.fileIds.length, 2);
      expect(() => choice.fileIds.clear(), throwsUnsupportedError);
    },
  );
  test('invalid archive/JSON cannot use file-only partial recovery', () async {
    final controller = ImportDecision(
      validate: (_) => Future.error(const FormatException('invalid')),
      requireCurrent: () {},
    );
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.phase, ImportDecisionPhase.failed);
    expect(controller.source, isNull);
    expect(controller.canApprovePartial, false);
    expect(controller.approvePartial, throwsStateError);
  });
  for (final source in [
    decisionFixture(issue: 'ZIP_JSON_LIMIT'),
    decisionFixture(issue: 'AUDIO_FORMAT', issueId: fixture.id(99)),
  ]) {
    test(
      'non-file or foreign error cannot authorize partial import ${source.issues.single.code}/${source.issues.single.recordingId}',
      () async {
        final controller = ImportDecision(
          validate: (_) => Future.value(source),
          requireCurrent: () {},
        );
        addTearDown(controller.dispose);
        await controller.check();
        expect(controller.canApprovePartial, false);
        expect(controller.approvePartial, throwsStateError);
      },
    );
  }
  test(
    'cancel fences in-flight work and ignores a late validation result',
    () async {
      final completer = Completer<ValidatedImport>();
      late void Function() guard;
      final controller = ImportDecision(
        validate: (g) {
          guard = g;
          return completer.future;
        },
        requireCurrent: () {},
      );
      addTearDown(controller.dispose);
      final pending = controller.check();
      controller.cancel();
      expect(guard, throwsStateError);
      completer.complete(decisionFixture());
      await pending;
      expect(controller.phase, ImportDecisionPhase.cancelled);
      expect(controller.source, isNull);
      expect(controller.approval, isNull);
    },
  );
  test(
    'account fence change rejects a late result and any prior approval',
    () async {
      var valid = true;
      void fence() {
        if (!valid) throw StateError('account switched');
      }

      final controller = ImportDecision(
        validate: (_) => Future.value(decisionFixture()),
        requireCurrent: fence,
      );
      addTearDown(controller.dispose);
      await controller.check();
      final consent = controller.approveWhole();
      valid = false;
      expect(() => controller.requireConsent(consent), throwsStateError);
      await controller.check();
      expect(controller.phase, ImportDecisionPhase.failed);
      expect(controller.canApprovePartial, false);
    },
  );
  testWidgets(
    'small three-button screen keeps cancel visible and partial choice separate',
    (tester) async {
      tester.view.physicalSize = const Size(320, 440);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewPadding();
      });
      final controller = ImportDecision(
        validate: (_) => Future.value(decisionFixture(issue: 'AUDIO_FORMAT')),
        requireCurrent: () {},
      );
      addTearDown(controller.dispose);
      ImportConsent? consent;
      var cancelled = false;
      await controller.check();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: ImportDecisionScreen(
            controller: controller,
            onApproved: (c) {
              consent = c;
            },
            onCancel: () {
              cancelled = true;
            },
          ),
        ),
      );
      expect(find.text('전체 복원 중단'), findsOneWidget);
      expect(find.text('검증한 항목으로 미리보기'), findsNothing);
      expect(consent, isNull);
      await tester.ensureVisible(find.text('정상 정보·파일만 미리보기'));
      await tester.tap(find.text('정상 정보·파일만 미리보기'));
      await tester.pump();
      expect(consent!.partial, true);
      expect(consent!.fileIds, {fixture.id(2)});
      expect(find.textContaining('아직 복원되지 않았습니다'), findsOneWidget);
      await tester.ensureVisible(find.text('취소'));
      await tester.pump();
      expect(tester.getRect(find.text('취소')).bottom, lessThanOrEqualTo(392));
      await tester.tap(find.text('취소'));
      await tester.pump();
      expect(cancelled, true);
      expect(() => controller.requireConsent(consent!), throwsStateError);
    },
  );
}
