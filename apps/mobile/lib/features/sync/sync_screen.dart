import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/database/local_models.dart';
import '../../core/sync/canonical_conflict_plan.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/feature_icon.dart';
import '../../core/widgets/ui_controls.dart';
import 'conflict_screen.dart';
import 'sync_controller.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({required this.controller, super.key});
  final SyncController controller;
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  String _name(LocalEntity entity) => switch (entity) {
    LocalEntity.song => '곡 정보',
    LocalEntity.recording => '녹음 정보',
    LocalEntity.tag => '태그',
    _ => '기타 정보',
  };
  String _state(SyncItem item) {
    if (item.retry?.originalKeyCorrection == true) {
      return '원곡 기준 키 설정을 그대로 다시 전송할 수 있어요';
    }
    if (item.mutation.state == 'CONFLICT') return '서버 값과 입력을 검토해야 해요';
    if (item.mutation.state == 'FAILED') return '입력 또는 전송 조건을 확인해 주세요';
    if (item.mutation.state == 'SENDING') return '전송 결과를 확인하고 있어요';
    if (item.retry?.mode == 'BLOCKED') return '연결·로그인·전송 조건 확인이 필요해요';
    if (item.retry?.mode == 'MANUAL_REQUIRED') {
      return '자동 재시도를 마쳤거나 이전 전송 이력 확인이 필요해요';
    }
    if (item.retry?.mode == 'AUTO') {
      return widget.controller.needsResume
          ? '자동 전송이 멈춰 있어요'
          : '다음 자동 재시도를 기다리고 있어요';
    }
    return '선행 정보 또는 전송을 기다리고 있어요';
  }

  Future<void> _review(SyncItem item) async {
    final controller = widget.controller;
    final actions = controller.conflicts;
    if (actions == null || controller.busy) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ConflictScreen(actions: actions, opId: item.mutation.opId),
      ),
    );
    if (!mounted) return;
    await controller.refresh();
    if (saved == true &&
        controller.maySend &&
        controller.backend.automaticFollowupAllowed) {
      await controller.wake();
    }
  }

  Future<void> _canonical(CanonicalConflictReview item) async {
    final controller = widget.controller;
    final actions = controller.conflicts;
    if (actions is! CanonicalConflictActions || controller.busy) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CanonicalConflictScreen(
          actions: actions as CanonicalConflictActions,
          intentId: item.intentId,
        ),
      ),
    );
    if (!mounted) return;
    await controller.refresh();
    if (saved == true &&
        controller.maySend &&
        controller.backend.automaticFollowupAllowed) {
      await controller.wake();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(context, title: const Text('동기화 상태')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final state = widget.controller;
          return ListView(
            padding: AppLayout.bodyPadding,
            children: [
              AppPanel(
                child: Column(
                  children: [
                    FeatureIcon(
                      state.busy ? Icons.sync : Icons.cloud_outlined,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.busy
                          ? '변경사항을 확인하고 있어요'
                          : state.needsResume
                          ? '연결을 기다리고 있어요'
                          : !state.loaded
                          ? '동기화 상태 확인 중'
                          : state.items.isEmpty && state.canonicalItems.isEmpty
                          ? '대기 중인 변경이 없어요'
                          : '확인이 필요한 변경이 있어요',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: state.busy || !state.maySend ? null : state.resume,
                child: const Text('다시 동기화'),
              ),
              const SizedBox(height: AppSpacing.sm),
              const ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('정보와 녹음 파일', style: TextStyle(fontSize: 12)),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text(
                      '곡·메모 등 정보의 동기화와 녹음 파일의 서버 보관은 별개예요. 녹음 파일은 각 녹음 상세에서 확인해 주세요. 다시 동기화를 누르면 전송 가능한 대기 정보도 함께 처리해요.',
                      style: TextStyle(fontSize: 12, height: 1.85),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.message != null) Text(state.message!),
              if (state.statusMessage != null) Text(state.statusMessage!),
              if (state.needsResume)
                const Text('자동 전송을 잠시 멈췄어요. 연결과 로그인 상태를 확인한 뒤 전송을 다시 시도해 주세요.'),
              if (state.needsResume)
                OutlinedButton(
                  onPressed: state.busy || !state.maySend ? null : state.resume,
                  child: const Text('전송 다시 시도'),
                ),
              if (!state.loaded && state.message == null)
                const Center(child: CircularProgressIndicator()),
              if (state.loaded &&
                  state.items.isEmpty &&
                  state.canonicalItems.isEmpty &&
                  state.message == null &&
                  state.statusMessage == null)
                const Text('대기 중인 정보가 없어요.'),
              for (final item in state.canonicalItems)
                Card(
                  child: ListTile(
                    title: const Text('같은 곡의 개인 편집'),
                    subtitle: Text(
                      item.state == 'QUEUED'
                          ? '선택을 저장했어요. 서버 전송·충돌 해결을 기다리고 있어요.'
                          : item.blockedReason ??
                                '서버 값과 보존된 입력 중 사용할 값을 선택해 주세요.',
                    ),
                    trailing: item.state == 'OPEN'
                        ? TextButton(
                            onPressed: state.busy
                                ? null
                                : () => _canonical(item),
                            child: const Text('개인 편집 검토'),
                          )
                        : null,
                  ),
                ),
              for (final item in state.items)
                Card(
                  child: ListTile(
                    title: Text(_name(item.mutation.entity)),
                    subtitle: Text(
                      item.pendingReview
                          ? '앞선 변경 해결 후 보존한 입력이에요. 최신 서버 값과 다시 비교해 주세요.'
                          : _state(item),
                    ),
                    trailing:
                        (item.mutation.state == 'CONFLICT' ||
                                item.pendingReview) &&
                            state.conflicts != null
                        ? TextButton(
                            onPressed: state.busy ? null : () => _review(item),
                            child: const Text('변경 검토'),
                          )
                        : item.retry?.canRetryManually == true
                        ? TextButton(
                            onPressed: state.busy || !state.maySend
                                ? null
                                : () => state.retry(item),
                            child: const Text('재시도'),
                          )
                        : null,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: state.busy ? null : state.refresh,
                child: const Text('상태 다시 확인'),
              ),
              if (state.busy) const LinearProgressIndicator(),
            ],
          );
        },
      ),
    ),
  );
}
