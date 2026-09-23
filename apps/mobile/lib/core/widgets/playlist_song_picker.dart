import 'package:flutter/material.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/content_state.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/song_row.dart';

enum SongListPhase { ready, loading, error, waiting }

/// The caller supplies only the current account's ACTIVE registered songs and
/// resolves existing playlist membership (including matching TJ candidates).
/// Each successful add is immediate; Done/back does not undo earlier adds.
class PlaylistSongPicker extends StatefulWidget {
  const PlaylistSongPicker({
    required this.playlistId,
    required this.playlistTitle,
    required this.songs,
    required this.includedSongIds,
    required this.onAdd,
    required this.onDiscover,
    required this.onDone,
    this.phase = SongListPhase.ready,
    this.onRetry,
    super.key,
  });

  final String playlistId;
  final String playlistTitle;
  final List<RegisteredSongViewData> songs;
  final Set<SongId> includedSongIds;
  final Future<void> Function(String playlistId, SongId songId) onAdd;
  final VoidCallback onDiscover;
  final VoidCallback onDone;
  final SongListPhase phase;
  final VoidCallback? onRetry;

  @override
  State<PlaylistSongPicker> createState() => _PlaylistSongPickerState();
}

class _PlaylistSongPickerState extends State<PlaylistSongPicker> {
  final _query = TextEditingController();
  final _added = <SongId>{};
  SongId? _busy;
  SongId? _failed;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant PlaylistSongPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlistId != widget.playlistId) {
      _generation++;
      _query.clear();
      _added.clear();
      _busy = null;
      _failed = null;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _included(SongId id) => widget.includedSongIds.contains(id) || _added.contains(id);

  Future<void> _add(SongId id) async {
    if (_busy != null || _included(id) || widget.phase != SongListPhase.ready) {
      return;
    }
    final generation = _generation;
    final playlistId = widget.playlistId;
    setState(() {
      _busy = id;
      _failed = null;
    });
    try {
      await widget.onAdd(playlistId, id);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _added.add(id);
        _busy = null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _failed = id;
        _busy = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = trimContractWhitespace(_query.text).toLowerCase();
    final visible = widget.songs.where((song) =>
      song.title.toLowerCase().contains(query) || song.artist.toLowerCase().contains(query),
    ).toList();
    final failed = _failed;
    return CustomScrollView(
      key: PageStorageKey('playlist-picker-${widget.playlistId}'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          sliver: SliverList.list(children: [
            Text(widget.playlistTitle, style: AppTypography.sheetTitle),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _query,
              decoration: const InputDecoration(labelText: '곡명 또는 가수 검색', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('이 목록에 추가된 곡은 다시 담을 수 없어요.', style: AppTypography.supporting),
            if (_busy != null)
              const ContentState(phase: ContentPhase.loading, title: '곡을 추가하고 있어요.'),
            if (failed != null)
              ContentState(
                phase: ContentPhase.error,
                title: '곡을 추가하지 못했어요.',
                message: '연결 상태를 확인한 뒤 다시 시도해 주세요.',
                onRetry: widget.phase == SongListPhase.ready &&
                    !_included(failed) && widget.songs.any((song) => song.id == failed)
                    ? () => _add(failed) : null,
              ),
            if (widget.phase != SongListPhase.ready)
              ContentState(
                phase: switch (widget.phase) {
                  SongListPhase.loading => ContentPhase.loading,
                  SongListPhase.error => ContentPhase.error,
                  _ => ContentPhase.waiting,
                },
                title: switch (widget.phase) {
                  SongListPhase.loading => '내 곡을 불러오고 있어요.',
                  SongListPhase.error => '내 곡을 불러오지 못했어요.',
                  _ => '내 곡 목록을 준비하고 있어요.',
                },
                onRetry: widget.phase == SongListPhase.error ? widget.onRetry : null,
              )
            else if (visible.isEmpty)
              ContentState(
                phase: ContentPhase.empty,
                title: query.isEmpty ? '등록된 내 곡이 없습니다' : '검색 결과가 없어요.',
                message: query.isEmpty ? '새 곡 찾기에서 원하는 곡을 찾아보세요.' : '곡명이나 가수를 다시 확인해 주세요.',
              )
            else
              Text('${visible.length}곡', style: AppTypography.supporting),
          ]),
        ),
        if (widget.phase == SongListPhase.ready)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final song = visible[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SongRow.registered(
                    key: ValueKey('pick-${song.id.value}'),
                    song: song,
                    alreadyAdded: _included(song.id),
                    onTap: _busy == null ? () => _add(song.id) : null,
                  ),
                );
              },
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          sliver: SliverList.list(children: [
            OutlinedButton(onPressed: _busy == null ? widget.onDiscover : null, child: const Text('새 곡 찾기')),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(onPressed: _busy == null ? widget.onDone : null, child: const Text('완료')),
          ]),
        ),
      ],
    );
  }
}
