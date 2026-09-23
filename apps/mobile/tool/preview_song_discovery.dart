import 'package:flutter/material.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/content_state.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/playlist_song_picker.dart';
import 'package:song_record/core/widgets/song_discovery_sheet.dart';

// Deliberately separate entry point: no production route or real storage.
void main() => runApp(MaterialApp(theme: AppTheme.dark(), home: const DiscoveryPreview()));

final _songs = [
  for (var i = 1; i <= 3; i++)
    RegisteredSongViewData(
      id: SongId('00000000-0000-4000-8000-00000000000$i'),
      title: ['아침 노래', '저녁 노래', '긴 제목이 있는 연습용 노래 샘플'][i - 1],
      artist: ['Sample Band', '샘플 가수', '연습 가수'][i - 1],
      version: VersionCode.normal,
    ),
];

class DiscoveryPreview extends StatelessWidget {
  const DiscoveryPreview({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('새 곡 찾기 미리보기')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('메모리 샘플 · 실제 곡과 플레이리스트는 바뀌지 않아요.'),
          for (final title in ['오늘 부를 곡', '연습할 곡'])
            ListTile(
              title: Text(title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
                builder: (_) => _PlaylistPreview(id: title, title: title),
              )),
            ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('공통 상태 샘플')),
                body: SafeArea(child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const ContentState(phase: ContentPhase.loading, title: '불러오고 있어요.'),
                    const ContentState(phase: ContentPhase.empty, title: '아직 담은 곡이 없어요.'),
                    ContentState(
                      phase: ContentPhase.error,
                      title: '연결하지 못했어요.',
                      onRetry: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('샘플 재시도 동작을 확인했어요.')),
                      ),
                    ),
                    const ContentState(phase: ContentPhase.waiting, title: '처리를 기다리고 있어요.'),
                  ],
                )),
              ),
            )),
            child: const Text('공통 상태 보기'),
          ),
        ],
      ),
    ),
  );
}

class _PlaylistPreview extends StatefulWidget {
  const _PlaylistPreview({required this.id, required this.title});
  final String id;
  final String title;

  @override
  State<_PlaylistPreview> createState() => _PlaylistPreviewState();
}

class _PlaylistPreviewState extends State<_PlaylistPreview> {
  final _included = <SongId>{};

  Future<void> _discover(BuildContext sourceContext, {bool fromPicker = false}) async {
    final result = await showSongDiscoverySheet(
      context: sourceContext,
      playlistId: widget.id,
      playlistTitle: widget.title,
    );
    if (!mounted || !sourceContext.mounted || result == null) {
      return;
    }
    if (result.destination == SongDiscoveryDestination.mySongs) {
      if (fromPicker) {
        return;
      }
      await Navigator.of(sourceContext).push<void>(MaterialPageRoute<void>(
        builder: (pickerContext) => Scaffold(
          appBar: AppBar(title: const Text('내 곡에서 선택')),
          body: SafeArea(child: PlaylistSongPicker(
            playlistId: widget.id,
            playlistTitle: widget.title,
            songs: _songs,
            includedSongIds: _included,
            onAdd: (playlistId, songId) async {
              if (playlistId != widget.id) {
                throw StateError('목록 문맥 불일치');
              }
              _included.add(songId);
            },
            onDiscover: () => _discover(pickerContext, fromPicker: true),
            onDone: () => Navigator.of(pickerContext).pop(),
          )),
        ),
      ));
      if (mounted) {
        setState(() {});
      }
    } else {
      await Navigator.of(sourceContext).push<void>(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(result.destination == SongDiscoveryDestination.charts ? '인기 차트' : '검색')),
          body: SafeArea(child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('돌아갈 목록: ${widget.title}'),
              const ContentState(phase: ContentPhase.waiting, title: '외부 곡 조회를 준비하고 있어요.'),
            ],
          )),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('메모리 샘플 · ${_included.length}곡'),
        if (_included.isEmpty)
          const ContentState(phase: ContentPhase.empty, title: '아직 담은 곡이 없어요.'),
        for (final song in _songs.where((song) => _included.contains(song.id)))
          ListTile(title: Text(song.title), subtitle: Text(song.artist)),
        FilledButton(onPressed: () => _discover(context), child: const Text('곡 추가')),
      ],
    )),
  );
}
