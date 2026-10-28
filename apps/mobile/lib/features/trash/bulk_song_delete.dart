import 'package:flutter/material.dart';

import 'trash_screens.dart';
import 'trash_workflow.dart';

/// Loads all preview versions before enabling the explicit delete action.
/// Successful requests are removed from the retry set after partial failure.
Future<bool> showBulkSongDelete(
  BuildContext context, {
  required List<String> ids,
  required TrashActions actions,
  required bool Function() isCurrent,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) =>
          _BulkSongDelete(ids: ids, actions: actions, isCurrent: isCurrent),
    ) ??
    false;

class _BulkSongDelete extends StatefulWidget {
  const _BulkSongDelete({
    required this.ids,
    required this.actions,
    required this.isCurrent,
  });
  final List<String> ids;
  final TrashActions actions;
  final bool Function() isCurrent;
  @override
  State<_BulkSongDelete> createState() => _BulkSongDeleteState();
}

class _BulkSongDeleteState extends State<_BulkSongDelete> {
  final previews = <String, Map<String, dynamic>>{};
  final completed = <String>{};
  bool busy = true;
  String mode = 'SONG_ONLY';
  String? error;
  bool get current => mounted && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
      previews.clear();
    });
    try {
      for (final id in widget.ids.where((id) => !completed.contains(id))) {
        if (!current) throw StateError('Account changed');
        final preview = await widget.actions.preview(id);
        if (!current) throw StateError('Account changed');
        previews[id] = preview;
      }
    } catch (e) {
      if (mounted) setState(() => error = trashError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!current || busy || error != null) return;
    setState(() => busy = true);
    try {
      for (final entry in previews.entries) {
        if (completed.contains(entry.key)) continue;
        if (!current) throw StateError('Account changed');
        await widget.actions.trashSong(
          entry.key,
          mode,
          entry.value['preview_version'] as String,
        );
        completed.add(entry.key);
      }
      if (mounted && widget.isCurrent()) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => error = '${completed.length}곡 처리 완료. ${trashError(e)}');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('선택한 ${widget.ids.length}곡 삭제'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('삭제한 곡은 휴지통으로 이동해요. 연결된 녹음은 어떻게 할까요?'),
            RadioGroup<String>(
              groupValue: mode,
              onChanged: (v) {
                if (!busy) setState(() => mode = v!);
              },
              child: Column(
                children: const [
                  RadioListTile(
                    value: 'SONG_ONLY',
                    title: Text('곡만 삭제 · 녹음 유지'),
                  ),
                  RadioListTile(
                    value: 'SONG_AND_RECORDINGS',
                    title: Text('곡과 녹음 함께 삭제'),
                  ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        if (error != null)
          TextButton(onPressed: busy ? null : load, child: const Text('다시 확인')),
        FilledButton(
          onPressed: busy || error != null || !widget.isCurrent() ? null : save,
          child: const Text('삭제'),
        ),
      ],
    ),
  );
}
