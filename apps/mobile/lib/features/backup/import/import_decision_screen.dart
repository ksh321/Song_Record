import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/ui_controls.dart';
import 'import_decision.dart';
import 'import_validation.dart';

String importIssueLabel(String code) => switch (code) {
  'MISSING_AUDIO' => '백업에 녹음 파일이 없어요',
  'AUDIO_HASH_OR_SIZE' => '녹음 파일이 백업 정보와 달라요',
  'AUDIO_FORMAT' => '녹음 파일을 정상적으로 읽을 수 없어요',
  'AUDIO_INSPECTION_TIMEOUT' => '음원 검사 시간 초과',
  _ => '백업 검사 오류',
};

class ImportDecisionScreen extends StatefulWidget {
  const ImportDecisionScreen({
    required this.controller,
    required this.onApproved,
    required this.onCancel,
    this.progress,
    super.key,
  });
  final ImportDecision controller;
  final void Function(ImportConsent consent) onApproved;
  final VoidCallback onCancel;
  final ValueListenable<String?>? progress;
  @override
  State<ImportDecisionScreen> createState() => _ImportDecisionScreenState();
}

class _ImportDecisionScreenState extends State<ImportDecisionScreen> {
  ImportDecision get controller => widget.controller;
  ValueListenable<String?>? get progress => widget.progress;
  VoidCallback get onCancel => widget.onCancel;
  void Function(ImportConsent) get onApproved => widget.onApproved;
  bool scheduled = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(advance);
    advance();
  }

  @override
  void didUpdateWidget(covariant ImportDecisionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(advance);
      controller.addListener(advance);
      advance();
    }
  }

  // Validation and preview never apply data. Damaged backups still require
  // the separate partial-recovery choice, and final import remains explicit.
  void advance() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted) return;
      if (controller.phase == ImportDecisionPhase.ready) {
        unawaited(controller.check());
      } else if (controller.canApproveWhole) {
        try {
          final consent = controller.approveWhole();
          controller.requireConsent(consent);
          onApproved(consent);
        } on StateError {
          controller.cancel();
        }
      }
    });
  }

  @override
  void dispose() {
    controller.removeListener(advance);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, progress]),
    builder: (context, _) {
      final source = controller.source;
      void cancel() {
        controller.cancel();
        onCancel();
      }

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) cancel();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('백업 가져오기'),
            leading: BackButton(onPressed: cancel),
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: AppLayout.bodyPadding,
              children: [
                const Text('검사와 미리보기 단계에서는 기존 정보와 정상 파일을 변경하지 않습니다.'),
                if (progress?.value != null) ...[
                  const LinearProgressIndicator(),
                  Text(progress!.value!),
                ],
                if (controller.busy) const LinearProgressIndicator(),
                if (controller.busy) const Text('백업과 녹음 파일을 확인하고 있어요'),
                if (controller.phase == ImportDecisionPhase.failed) ...[
                  const Text(
                    '전체 복원 중단',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  const Text(
                    '이 계정의 백업인지 또는 정상 파일인지 확인하지 못했어요. 원본 백업 파일을 다시 선택해 주세요.',
                  ),
                ],
                if (source != null) ...[
                  Text(
                    '백업 정보 ${source.manifest.metadataCount}개 · 정상 포함 파일 ${controller.normalFileIds.length}개',
                  ),
                  Text(
                    '백업에 미포함 ${source.manifest.missingAudioCount}개 · 선택 제외 ${source.manifest.excludedAudioCount}개',
                  ),
                ],
                if (controller.phase == ImportDecisionPhase.blocked) ...[
                  const Text(
                    '전체 복원 중단',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  const Text('손상 파일을 자동으로 건너뛰지 않습니다. 아직 가져온 항목은 없습니다.'),
                  for (final issue in source!.issues.take(10))
                    Text(
                      '${issue.recordingId == null ? '검사 항목' : '녹음 파일'} · ${importIssueLabel(issue.code)}',
                    ),
                  if (source.issues.length > 10)
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ImportErrorList(issues: source.issues),
                        ),
                      ),
                      child: Text('오류 ${source.issues.length}개 전체 보기'),
                    ),
                  if (controller.canApprovePartial) ...[
                    Text(
                      '별도 선택: 정상 정보와 파일만 미리보기. 오류 파일 ${controller.excludedFileIds.length}개는 제외되며 누락 내역은 유지됩니다.',
                    ),
                    OutlinedButton(
                      onPressed: () => onApproved(controller.approvePartial()),
                      child: const Text('정상 정보·파일만 미리보기'),
                    ),
                  ],
                ],
                if (controller.canApproveWhole) const Text('가져올 내용을 확인하고 있어요'),
                if (controller.phase == ImportDecisionPhase.approved)
                  const Text('미리보기 선택됨 · 아직 복원되지 않았습니다.'),
                if (controller.phase == ImportDecisionPhase.cancelled)
                  const Text('가져오기 취소 · 기존 정보와 파일 보존'),
                const SizedBox(height: AppSpacing.lg),
                TextButton(onPressed: cancel, child: const Text('취소')),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ImportErrorList extends StatelessWidget {
  const ImportErrorList({required this.issues, super.key});
  final List<ImportValidationIssue> issues;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('파일 검사 오류 ${issues.length}개')),
    body: SafeArea(
      top: false,
      child: ListView.builder(
        itemCount: issues.length,
        itemBuilder: (context, index) {
          final issue = issues[index];
          return ListTile(
            title: Text(issue.recordingId == null ? '검사 항목' : '녹음 파일'),
            subtitle: Text(importIssueLabel(issue.code)),
          );
        },
      ),
    ),
  );
}
