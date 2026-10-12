import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import 'import_outcome.dart';
import 'import_outcome_view.dart';

class ImportApplyPreview extends StatefulWidget {
  const ImportApplyPreview({
    required this.information,
    required this.files,
    required this.held,
    required this.conflicts,
    required this.requireCurrent,
    required this.accountChanges,
    required this.apply,
    super.key,
  });
  final int information, files, held, conflicts;
  final VoidCallback requireCurrent;
  final Listenable accountChanges;
  final Future<ImportOutcome> Function(VoidCallback guard)? apply;
  @override
  State<ImportApplyPreview> createState() => _State();
}

class _State extends State<ImportApplyPreview> {
  bool busy = false;
  int generation = 0;
  String? message;
  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> start() async {
    if (busy || widget.apply == null) return;
    final epoch = ++generation;
    void guard() {
      widget.requireCurrent();
      if (!mounted || epoch != generation) {
        throw StateError('Import application cancelled');
      }
    }

    setState(() {
      busy = true;
      message = null;
    });
    try {
      guard();
      final result = await widget.apply!(guard);
      guard();
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ListenableBuilder(
            listenable: widget.accountChanges,
            builder: (_, _) {
              try {
                guard();
                return Scaffold(
                  appBar: AppBar(title: const Text('가져오기 결과')),
                  body: ImportOutcomeView(result: result),
                );
              } catch (_) {
                return const Scaffold(
                  body: SafeArea(child: Text('계정이 바뀌었습니다. 설정으로 돌아가 주세요.')),
                );
              }
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted && epoch == generation) {
        setState(
          () => message = '적용을 완료하지 못했어요. 최신 상태·지원되는 변경을 다시 대조해 주세요. 이미 완료된 항목과 중단 기록·원본은 보존합니다.',
        );
      }
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('가져오기 대조 결과')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const Text('현재 계정의 최신 서버 상태와 선택한 실제 백업을 대조했습니다. 아직 적용하지 않았습니다.'),
          Text('검증된 정보: ${widget.information}'),
          Text('검증된 파일: ${widget.files}'),
          Text('삭제·상태·금영 후보 보류: ${widget.held}'),
          Text('검토할 충돌: ${widget.conflicts}'),
          if (busy) const LinearProgressIndicator(),
          if (message != null) Text(message!),
          const Text('적용을 시작한 뒤 뒤로 나가면 완료된 항목은 유지하고 남은 작업을 중단합니다.'),
          FilledButton(
            onPressed: busy || widget.conflicts > 0 || widget.apply == null
                ? null
                : () => unawaited(start()),
            child: const Text('대조한 정보와 파일 적용'),
          ),
        ],
      ),
    ),
  );
}
