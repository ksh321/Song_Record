import 'package:flutter/material.dart';

import '../../core/domain/song_types.dart';
import '../../core/widgets/music_view_data.dart';
import 'recording_audio_panel.dart';
import 'recording_player_screen.dart';

/// A single player route for full lists, linked rows and retention roles.
void openRecordingPlayback(
  BuildContext context,
  RecordingViewData recording, {
  bool autoplay = true,
  VoidCallback? onDetails,
  bool Function()? isCurrent,
}) {
  if (isCurrent?.call() == false) return;
  final access = context.getInheritedWidgetOfExactType<RecordingAudioAccess>();
  final store = access?.store();
  if (access == null || store == null) {
    onDetails?.call();
    return;
  }
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => RecordingPlayerScreen(
        recordingId: recording.id.value,
        autoplay: autoplay,
        title:
            '${recording.snapshot.artist} · ${recording.snapshot.title} ${formatMusicalKey(recording.snapshot.key)}',
        initialDuration: recording.duration.inMilliseconds,
        onDetails: onDetails,
        createPlayer: () => access.createPlayer(store),
      ),
    ),
  );
}
