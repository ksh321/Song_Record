import 'package:flutter/material.dart';

import '../files/recording_file_status.dart';

/// Availability comes from verified files/STORED evidence, never role/pin selection.
class RecordingPlaybackActions extends StatelessWidget {
  const RecordingPlaybackActions({
    super.key,
    required this.status,
    this.onPlay,
  });
  final RecordingFileStatus status;
  final VoidCallback? onPlay;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton(
        onPressed: status.canPlay ? onPlay : null,
        child: const Text('재생'),
      ),
      if (!status.canPlay) ...[
        Text(status.playbackUnavailableLabel),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('파일 복원 안내'),
              content: const Text(RecordingFileStatus.restorationGuide),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
              ],
            ),
          ),
          child: const Text('파일 복원 안내'),
        ),
      ],
    ],
  );
}
