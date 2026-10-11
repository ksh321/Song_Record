import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import 'export_controller.dart';
import 'export_manifest.dart';
import 'export_zip.dart';

String backupMissingLabel(ExportMissingReason reason) => switch (reason) {
  ExportMissingReason.offlineServerOnly => '서버 전용 파일 · 온라인 백업 필요',
  ExportMissingReason.fileNotOnDevice => '다른 기기 또는 이전 백업에서 파일 필요',
  ExportMissingReason.fileDeleted => '기준 이후 파일 삭제',
  ExportMissingReason.downloadFailed => '파일 다운로드 실패',
  ExportMissingReason.checksumMismatch => '파일 체크섬 불일치',
  ExportMissingReason.incompleteRecording => '미완성·손상 녹음',
  ExportMissingReason.trashNotSelected => '휴지통 파일 선택 제외',
  ExportMissingReason.notCollected => '아직 수집하지 않음',
};

String backupResultLabel(ExportManifest manifest) => !manifest.online
    ? '이 기기 기준 백업 완료 · 다른 기기의 최신 변경은 포함되지 않을 수 있습니다.'
    : manifest.missingAudioCount > 0
    ? '백업 완료 · 일부 파일 미포함'
    : '백업 완료';

class ExportScreen extends StatefulWidget {
  const ExportScreen({required this.controller, super.key});
  final ExportController controller;
  @override
  State<ExportScreen> createState() => _State();
}

class _State extends State<ExportScreen> {
  bool online = true, trash = false, accepted = false;
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.restore());
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller, manifest = controller.manifest;
      final steps = <BackupPhase, String>{
        BackupPhase.ready: '백업 준비',
        BackupPhase.preparing: '진행 중 녹음 종료·공간 확인',
        BackupPhase.baseline: '기준 메타정보 확인',
        BackupPhase.collecting: '음성 파일 수집',
        BackupPhase.zip: 'ZIP 생성·검증',
        BackupPhase.saving: '시스템 파일 선택기 저장',
        BackupPhase.completed: manifest == null
            ? '저장 완료'
            : backupResultLabel(manifest),
        BackupPhase.cancelled: '백업 취소 · 내부 사본과 원본 보존',
        BackupPhase.failed: '백업 미완료',
        BackupPhase.resumable: '이전 백업 작업 재개 가능',
      };
      return PopScope(
        canPop: !controller.busy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('백업 내보내기'),
            leading: IconButton(
              tooltip: '뒤로가기',
              icon: const Icon(Icons.arrow_back),
              onPressed: controller.busy
                  ? null
                  : () => Navigator.maybePop(context),
            ),
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const Text(backupPrivacyNotice),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: accepted,
                  onChanged: controller.busy
                      ? null
                      : (value) => setState(() {
                          accepted = value ?? false;
                        }),
                  title: const Text('포함 자료와 비암호화 저장 안내를 확인했어요'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: online,
                  onChanged: controller.busy
                      ? null
                      : (value) => setState(() {
                          online = value;
                        }),
                  title: const Text('온라인 서버 기준 포함'),
                  subtitle: const Text(
                    '끄면 이 기기 기준입니다. 서버 전용 파일과 다른 기기의 최신 변경은 빠질 수 있어요.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: trash,
                  onChanged: controller.busy
                      ? null
                      : (value) => setState(() {
                          trash = value;
                        }),
                  title: const Text('휴지통 음성 파일도 포함'),
                ),
                const Text('녹음 중이면 먼저 안전하게 종료합니다. 저장 완료된 파일과 입력 대기 정보를 보존합니다.'),
                const SizedBox(height: AppSpacing.md),
                Text(
                  steps[controller.phase]!,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (controller.busy) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(),
                  Text('파일 ${controller.done} / ${controller.total}'),
                  OutlinedButton(
                    onPressed: controller.cancel,
                    child: const Text('백업 취소'),
                  ),
                ],
                if (controller.error != null)
                  Text(
                    controller.error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                if (manifest != null) ...[
                  Text(
                    '포함 정보 ${manifest.metadataCount}개 · 포함 파일 ${manifest.includedAudioCount}개 · 미포함 ${manifest.missingAudioCount}개 · 선택 제외 ${manifest.excludedAudioCount}개',
                  ),
                  Text('로컬 기준: ${manifest.localCutoffAt.toLocal()}'),
                  Text(
                    '서버 기준: ${manifest.serverCapturedAt?.toLocal() ?? "최신 서버 기준 아님"} · 커서 ${manifest.snapshotCursor ?? "미확인"}',
                  ),
                  const Text('기준 이후 수정·추가는 다음 새 백업에 포함됩니다.'),
                  Text(
                    '재개 고정 범위: ${manifest.online ? "온라인" : "이 기기"} · 휴지통 ${manifest.includeTrash ? "포함" : "제외"}. 위 선택은 새 백업에 적용됩니다.',
                  ),
                  for (final entry in manifest.files.where((f) => !f.included))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(backupMissingLabel(entry.missingReason!)),
                      subtitle: Text('녹음 ${entry.recordingId}'),
                    ),
                ],
                if (!controller.busy) ...[
                  if (controller.job != null &&
                      controller.phase != BackupPhase.completed)
                    FilledButton(
                      onPressed: accepted
                          ? () => controller.start(
                              online: online,
                              includeTrash: trash,
                            )
                          : null,
                      child: const Text('고정 기준으로 재개·저장 재시도'),
                    ),
                  FilledButton(
                    onPressed: accepted
                        ? () => controller.start(
                            online: online,
                            includeTrash: trash,
                            fresh: true,
                          )
                        : null,
                    child: const Text('새 백업 시작'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
