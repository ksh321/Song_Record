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
    this.storageBuilder,
    required super.child,
    super.key,
  });
  final AccountStore? Function() store;
  final AudioPlayback Function(AccountStore) createPlayer;
  final Listenable changes;
  final VoidCallback refresh;
  final Widget Function(BuildContext, String)? storageBuilder;
  @override
  bool updateShouldNotify(RecordingAudioAccess oldWidget) => true;
}

class RecordingAudioPanel extends StatefulWidget {
  const RecordingAudioPanel(
    this.recordingId, {
    super.key,
    this.compact = false,
    this.showStatus = true,
    this.showPlayback = true,
  });
  final String recordingId;
  final bool compact;
  final bool showStatus;
  final bool showPlayback;
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
              if (widget.showStatus && widget.compact)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    value.serverStored
                        ? '서버에 보관됨'
                        : value.device == DeviceAudioState.available
                        ? '이 기기에 있음'
                        : '파일 상태 확인',
                    style: const TextStyle(fontSize: 12),
                  ),
                  children: [
                    Text(value.informationLabel),
                    Text(value.deviceLabel),
                    Text(value.serverLabel),
                    if (value.pinLabel != null) Text(value.pinLabel!),
                  ],
                )
              else if (widget.showStatus) ...[
                Text(value.informationLabel),
                Text(value.deviceLabel),
                Text(value.serverLabel),
                if (value.pinLabel != null) Text(value.pinLabel!),
              ],
              if (widget.showPlayback)
                RecordingPlaybackActions(status: value, onPlay: _play),
            ],
            if (widget.showStatus)
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
