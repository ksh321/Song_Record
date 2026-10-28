import 'package:flutter/material.dart';

import '../../core/database/account_store.dart';
import '../../core/files/device_file_cleanup.dart';
import '../../core/files/recording_export.dart';
import '../../core/widgets/app_page_bar.dart';
import '../../core/widgets/device_file_cleanup_button.dart';
import '../../core/widgets/ui_controls.dart';
import 'recording_audio_panel.dart';

class RecordingManageScreen extends StatefulWidget {
  const RecordingManageScreen({
    required this.id,
    required this.title,
    required this.artist,
    required this.isCurrent,
    this.deleteBuilder,
    super.key,
  });
  final String id, title, artist;
  final bool Function() isCurrent;
  final WidgetBuilder? deleteBuilder;
  @override
  State<RecordingManageScreen> createState() => _RecordingManageState();
}

class _RecordingManageState extends State<RecordingManageScreen> {
  AccountStore? lease;
  bool busy = false;
  String? message;
  bool get current =>
      mounted &&
      widget.isCurrent() &&
      lease != null &&
      context.getInheritedWidgetOfExactType<RecordingAudioAccess>()?.store() ==
          lease;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    lease ??= context
        .dependOnInheritedWidgetOfExactType<RecordingAudioAccess>()
        ?.store();
  }

  Future<void> export() async {
    if (!current || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('M4A 내보내기'),
        content: const Text(externalAudioCopyNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('저장 위치 선택'),
          ),
        ],
      ),
    );
    if (!current || confirmed != true) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final saved = await RecordingExport(lease!)
          .export(widget.id, title: widget.title, artist: widget.artist);
      if (current) {
        setState(() => message = saved ? '녹음 사본을 내보냈어요.' : '내보내기를 취소했어요.');
      }
    } catch (_) {
      if (current) {
        setState(() => message = '이 기기에 재생 가능한 파일이 있는지 확인해 주세요. 원본은 유지돼요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context
        .dependOnInheritedWidgetOfExactType<RecordingAudioAccess>();
    final enabled = current && !busy;
    return Scaffold(
      appBar: appPageBar(context, title: const Text('보관 관리')),
      body: SafeArea(
        child: ListView(
          padding: AppLayout.bodyPadding,
          children: [
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  RecordingAudioPanel(widget.id, showPlayback: false),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: enabled && access?.storageBuilder != null
                  ? () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            access!.storageBuilder!(context, widget.id),
                      ),
                    )
                  : null,
              child: const Text('고정 보관'),
            ),
            const SizedBox(height: 14),
            if (enabled) ...[
              DeviceFileCleanupButton(
                cleanup: DeviceFileCleanup(lease!),
                recordingId: widget.id,
                fullWidth: true,
              ),
              const SizedBox(height: 14),
            ],
            OutlinedButton(
              onPressed: enabled ? export : null,
              child: const Text('M4A 내보내기'),
            ),
            const SizedBox(height: 14),
            if (widget.deleteBuilder != null)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: enabled
                    ? () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(builder: widget.deleteBuilder!),
                      )
                    : null,
                child: const Text('녹음 삭제'),
              ),
            if (message != null) Text(message!),
            if (!current) const Text('계정이 변경됐어요. 돌아가 다시 열어 주세요.'),
          ],
        ),
      ),
    );
  }
}
