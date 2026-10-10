import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../auth/auth_session.dart';
import 'my_song_detail.dart';

enum SongAction { playlistAdd, delete }

/// P17 provides navigation only. P19/P20 supply mutation workflows and server previews.
class SongActionEntry extends StatefulWidget {
  const SongActionEntry({required this.action, required this.detail, this.auth, super.key});
  final SongAction action;
  final MySongDetail detail;
  final AuthController? auth;
  @override
  State<SongActionEntry> createState() => _SongActionEntryState();
}
class _SongActionEntryState extends State<SongActionEntry> {
  late final String scope = tag();
  bool invalidated = false;
  String tag() => '${widget.auth?.phase}:${widget.auth?.session?.userId}:${widget.auth?.session?.deviceId}';
  bool get current => !invalidated && scope == tag();
  void changed() { if (mounted && tag() != scope) setState(() => invalidated = true); }
  @override
  void initState() { super.initState(); widget.auth?.addListener(changed); }
  @override
  void dispose() { widget.auth?.removeListener(changed); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    Widget body() => SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (!current)
            const Text('계정이 변경됐어요. 내 곡 목록에서 다시 열어 주세요.')
          else ...[
            Text(
              widget.detail.song!.view.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(widget.detail.song!.view.artist),
            if (widget.action == SongAction.playlistAdd)
              const Text('플레이리스트 선택·추가 기능을 준비 중이에요. 아직 추가되지 않았어요.')
            else ...[
              Text('현재 기기에 연결된 활성 녹음 ${widget.detail.recordings.length}개'),
              const Text('삭제 전 서버에서 녹음·파일·고정 수를 다시 확인해야 해요.'),
              const Text(
                '곡만 삭제하고 녹음 유지 / 곡과 녹음 함께 삭제 중 선택할 수 있도록 삭제 기능을 준비 중이에요. 아직 삭제되지 않았어요.',
              ),
            ],
          ],
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('돌아가기'),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.action == SongAction.playlistAdd ? '플레이리스트 추가' : '곡 삭제'),
      ),
      body: body(),
    );
  }
}
