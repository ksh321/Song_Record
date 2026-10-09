import 'package:flutter/material.dart';

import '../files/device_file_cleanup.dart';

class DeviceFileCleanupButton extends StatefulWidget {
  const DeviceFileCleanupButton({
    super.key,
    required this.cleanup,
    required this.recordingId,
  });
  final DeviceFileCleanup cleanup;
  final String recordingId;
  @override
  State<DeviceFileCleanupButton> createState() => _State();
}

class _State extends State<DeviceFileCleanupButton> {
  bool busy = false;
  String message = '';
  Future<void> run() async {
    setState(() => busy = true);
    try {
      final preview = await widget.cleanup.preview(widget.recordingId);
      if (!mounted) return;
      bool loss = false;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('이 기기 파일 정리'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(preview.warning),
                if (preview.requiresLossAcknowledgement)
                  CheckboxListTile(
                    value: loss,
                    onChanged: (v) => setDialogState(() => loss = v ?? false),
                    title: const Text('파일을 복구하지 못할 수 있음을 이해했습니다'),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: preview.requiresLossAcknowledgement && !loss
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('이 기기 파일만 정리'),
              ),
            ],
          ),
        ),
      );
      if (confirm == true) {
        await widget.cleanup.confirm(
          preview,
          confirmed: true,
          lossAcknowledged: loss,
        );
        message = '이 기기 파일 정리 완료 · 녹음 정보 유지';
      } else {
        message = '정리 취소 · 원본 유지';
      }
    } catch (_) {
      message = '정리 결과를 확인할 수 없습니다. 파일 변경·계정·서버 정리 결과를 확인해 주세요.';
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
        child: const Text('이 기기 파일 정리'),
      ),
      if (message.isNotEmpty) Text(message),
    ],
  );
}
