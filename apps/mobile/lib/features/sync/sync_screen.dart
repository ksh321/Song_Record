import 'package:flutter/material.dart';

import '../../core/database/local_models.dart';
import '../../core/theme/app_tokens.dart';
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('동기화 상태')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final state = widget.controller;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const Text('이 기기의 전송 대기 정보'),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '재시도를 요청하면 전송 가능한 다른 대기 정보도 함께 처리해요. 파일 전송과 충돌 해결은 별도예요.',
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
                  state.message == null &&
                  state.statusMessage == null)
                const Text('대기 중인 정보가 없어요.'),
              for (final item in state.items)
                Card(
                  child: ListTile(
                    title: Text(_name(item.mutation.entity)),
                    subtitle: Text(_state(item)),
                    trailing: item.retry?.canRetryManually == true
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
