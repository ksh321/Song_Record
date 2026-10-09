import 'package:flutter/material.dart';
import 'package:song_record/core/files/recording_file_status.dart';
import 'package:song_record/core/theme/app_tokens.dart';

/// Information completion and physical backup are separate rows, never one success badge.
class RecordingFileStatusCard extends StatelessWidget {
  const RecordingFileStatusCard({required this.status, super.key});
  final RecordingFileStatus status;
  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.surface,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.informationLabel),
          Text(status.deviceLabel),
          Text(status.serverLabel),
          Text(status.waitingLabel),
          if (status.pinLabel != null) Text(status.pinLabel!),
        ],
      ),
    ),
  );
}
