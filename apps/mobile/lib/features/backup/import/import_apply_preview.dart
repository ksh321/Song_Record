import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/ui_controls.dart';
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
    appBar: AppBar(title: const Text('가져오기 미리보기')),
    body: SafeArea(
      child: ListView(
        padding: AppLayout.bodyPadding,
        children: [
          const Text('백업과 현재 기록을 확인했어요. 아래 내용을 확인하고 가져오기를 눌러 주세요.'),
          Text('가져올 정보 ${widget.information}개'),
          Text('가져올 녹음 파일 ${widget.files}개'),
          Text('이번에 가져오지 않는 항목 ${widget.held}개'),
          if (widget.held > 0)
            const Text(
              '이미 삭제한 기록, 현재 상태를 확인할 수 없는 항목, 다시 곡을 선택해야 하는 이전 금영 목록 항목은 가져오지 않아요. 원본 백업은 유지돼요.',
            ),
          if (widget.conflicts > 0)
            Text(
              '현재 기록과 내용이 다른 항목 ${widget.conflicts}개가 있어요. 기존 내용을 보호하기 위해 가져오기를 멈췄어요.',
            ),
          if (busy) const LinearProgressIndicator(),
          if (message != null) Text(message!),
          const Text('적용을 시작한 뒤 뒤로 나가면 완료된 항목은 유지하고 남은 작업을 중단합니다.'),
          FilledButton(
            onPressed: busy || widget.conflicts > 0 || widget.apply == null
                ? null
                : () => unawaited(start()),
            child: const Text('가져오기'),
          ),
        ],
      ),
    ),
  );
}
