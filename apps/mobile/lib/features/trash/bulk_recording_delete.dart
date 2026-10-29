import 'package:flutter/material.dart';

import 'trash_screens.dart';
import 'trash_workflow.dart';

Future<bool> showBulkRecordingDelete(
  BuildContext context, {
  required Map<String, String> recordings,
  required TrashActions actions,
  required bool Function() isCurrent,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BulkRecordingDelete(
        recordings: Map.unmodifiable(recordings),
        actions: actions,
        isCurrent: isCurrent,
      ),
    ) ??
    false;

class _BulkRecordingDelete extends StatefulWidget {
  const _BulkRecordingDelete({
    required this.recordings,
    required this.actions,
    required this.isCurrent,
  });
  final Map<String, String> recordings;
  final TrashActions actions;
  final bool Function() isCurrent;
  @override
  State<_BulkRecordingDelete> createState() => _State();
}

class _State extends State<_BulkRecordingDelete> {
  final completed = <String>{};
  bool confirmed = false, busy = false;
  String? error;
  Future<void> save() async {
    if (busy || !confirmed || !widget.isCurrent()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      for (final id in widget.recordings.keys) {
        if (completed.contains(id)) continue;
        if (!mounted || !widget.isCurrent()) {
          throw StateError('Account changed');
        }
        await widget.actions.trashRecording(id, true);
        completed.add(id);
      }
      if (mounted && widget.isCurrent()) {
        Navigator.pop(context, true);
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = '${completed.length}개 처리 완료. ${trashError(failure)}',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('선택한 ${widget.recordings.length}개 녹음 삭제'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in widget.recordings.entries)
              Text(
                '${completed.contains(entry.key) ? '✓ ' : ''}${entry.value}',
              ),
            const SizedBox(height: 12),
            const Text(
              '서버가 확정한 삭제 시각부터 7일 동안 휴지통에서 복원할 수 있어요. 고정 슬롯은 해제되며 복원해도 고정·대표는 자동으로 돌아오지 않아요.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: busy
                  ? null
                  : (v) => setState(() => confirmed = v ?? false),
              title: const Text('선택한 녹음 삭제와 고정 해제를 확인했어요'),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: busy || !confirmed || !widget.isCurrent() ? null : save,
          child: Text(
            busy
                ? '처리 중'
                : error == null
                ? '휴지통으로 이동'
                : '남은 녹음 다시 삭제',
          ),
        ),
      ],
    ),
  );
}
