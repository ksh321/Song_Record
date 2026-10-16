import 'package:flutter/material.dart';

import '../../core/audio/audio_player.dart';
import '../../core/database/account_store.dart';
import '../../core/files/recording_file_status.dart';
import '../../core/widgets/recording_playback_actions.dart';
import 'recording_player_screen.dart';

/// App-owned access, shared by all recording detail routes.
class RecordingAudioAccess extends InheritedWidget {
  const RecordingAudioAccess({
    required this.store,
    required this.createPlayer,
    required this.changes,
    required this.refresh,
    required super.child,
    super.key,
  });
  final AccountStore? Function() store;
  final AudioPlayback Function(AccountStore) createPlayer;
  final Listenable changes;
  final VoidCallback refresh;
  @override
  bool updateShouldNotify(RecordingAudioAccess oldWidget) => true;
}

class RecordingAudioPanel extends StatefulWidget {
  const RecordingAudioPanel(this.recordingId, {super.key});
  final String recordingId;
  @override
  State<RecordingAudioPanel> createState() => _RecordingAudioPanelState();
}

class _RecordingAudioPanelState extends State<RecordingAudioPanel> {
  RecordingAudioAccess? access;
  AccountStore? lease;
  Future<RecordingFileStatus>? status;
  bool invalidated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context
        .dependOnInheritedWidgetOfExactType<RecordingAudioAccess>();
    if (identical(access, next)) return;
    access?.changes.removeListener(_reload);
    access = next;
    lease ??= next?.store();
    next?.changes.addListener(_reload);
    _load();
  }

  void _load() {
    final store = lease;
    if (store == null) return;
    if (access?.store() != store) invalidated = true;
    if (invalidated) return;
    status = RecordingFileStatuses(store).read(widget.recordingId);
  }

  void _reload() {
    if (mounted) setState(_load);
  }

  @override
  void dispose() {
    access?.changes.removeListener(_reload);
    super.dispose();
  }

  void _play() {
    final store = lease;
    if (invalidated || store == null || access?.store() != store) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RecordingPlayerScreen(
          recordingId: widget.recordingId,
          createPlayer: () => access!.createPlayer(store),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (access == null) return const SizedBox.shrink();
    if (invalidated || lease == null) {
      return const Text('계정이 변경됐어요. 다시 열어 주세요.');
    }
    return FutureBuilder<RecordingFileStatus>(
      future: status,
      builder: (context, snapshot) {
        final value = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (snapshot.hasError)
              const Text('파일 상태를 확인하지 못했어요.')
            else if (value == null)
              const Text('파일 상태 확인 중')
            else ...[
              Text(value.informationLabel),
              Text(value.deviceLabel),
              Text(value.serverLabel),
              if (value.pinLabel != null) Text(value.pinLabel!),
              RecordingPlaybackActions(status: value, onPlay: _play),
            ],
            TextButton(
              onPressed: () {
                access!.refresh();
                _reload();
              },
              child: const Text('파일 상태 새로고침'),
            ),
          ],
        );
      },
    );
  }
}
