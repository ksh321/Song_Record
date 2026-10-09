import 'package:flutter/material.dart';

import '../files/recording_export.dart';

class RecordingExportButton extends StatefulWidget {
  const RecordingExportButton({
    super.key,
    required this.exporter,
    required this.recordingId,
    required this.title,
    required this.artist,
  });
  final RecordingExport exporter;
  final String recordingId, title, artist;
  @override
  State<RecordingExportButton> createState() => _State();
}

class _State extends State<RecordingExportButton> {
  bool busy = false;
  String message = '';
  Future<void> run() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('M4A 내보내기'),
        content: const Text(externalAudioCopyNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('저장 위치 선택'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => busy = true);
    try {
      final saved = await widget.exporter.export(
        widget.recordingId,
        title: widget.title,
        artist: widget.artist,
      );
      message = saved ? 'M4A 저장 완료 · 원본 유지' : '내보내기 취소 · 원본 유지';
    } catch (_) {
      message = '저장 실패 · 원본 유지. 저장 위치에 미완성 사본이 있을 수 있습니다.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      OutlinedButton(
        onPressed: busy ? null : run,
        child: Text(busy ? '저장 중' : 'M4A 내보내기'),
      ),
      if (message.isNotEmpty) Text(message),
    ],
  );
}
