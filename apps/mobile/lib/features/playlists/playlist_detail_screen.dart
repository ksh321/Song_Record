import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/widgets/music_view_data.dart';
import '../../core/widgets/song_row.dart';
import '../songs/my_song.dart';

import 'playlist_library.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.library,
    required this.id,
    this.afterSave,
  });
  final PlaylistLibrary library;
  final String id;
  final Future<void> Function()? afterSave;
  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  Map<String, dynamic>? parent;
  List<Map<String, dynamic>> items = [], songs = [];
  bool busy = false;
  String? error;
  Timer? _refresh;
  bool _loading = false;
  String? _fingerprint;
  @override
  void initState() {
    super.initState();
    reload();
    // Raw SQLite receipt writes do not invalidate Drift query watchers.
    // Refresh both entries and songs: an item-only ACK must also be visible.
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) => reload());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> reload() async {
    if (_loading) return;
    _loading = true;
    final library = widget.library, id = widget.id;
    try {
      final rows = await library.load();
      final selected = rows.where((x) => x['id'] == id).firstOrNull;
      final entries = await library.items(id);
      final available = await library.songs();
      final fingerprint = jsonEncode([selected, entries, available]);
      if (mounted &&
          library == widget.library &&
          id == widget.id &&
          (fingerprint != _fingerprint || error != null)) {
        setState(() {
          _fingerprint = fingerprint;
          parent = selected;
          items = entries;
          songs = available;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && library == widget.library && id == widget.id) {
        setState(() {
          _fingerprint = null;
          parent = null;
          items = [];
          songs = [];
          error = '목록을 불러오지 못했어요. 다시 시도해 주세요.';
        });
      }
    } finally {
      _loading = false;
    }
  }

  Widget? itemRow(Map<String, dynamic> item) {
    final songId = item['song_id'];
    if (songId != null) {
      final song = songs.where((s) => s['id'] == songId).firstOrNull;
      // A linked trashed/missing song must not reappear as a catalog candidate.
      return song == null ? null : SongRow.registered(song: MySong(song).view);
    }
    final snapshot = item['candidate_snapshot'];
    if (item['candidate_brand'] != 'TJ' || snapshot is! Map) return null;
    return SongRow.candidate(
      candidate: CandidateSongViewData(
        brand: CatalogBrand.tj,
        number: item['candidate_number'] as String,
        title: snapshot['title'] as String,
        artist: snapshot['artist'] as String,
      ),
      placement: CandidatePlacement.playlist,
    );
  }

  Future<void> add() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('내 곡 추가'),
        children: [
          for (final song in songs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, song['id'] as String),
              child: Text('${song['title']} · ${song['artist']}'),
            ),
          if (songs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('추가할 내 곡이 없어요.'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted || parent == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.library.addRegistered(parent!, selected)();
      await widget.afterSave?.call();
      await reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('목록 추가 요청 저장 완료')));
      }
    } catch (_) {
      if (mounted) setState(() => error = '추가 요청을 저장하지 못했어요. 최신 목록을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(parent?['name'] as String? ?? '플레이리스트')),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null) Text(error!),
            FilledButton(
              onPressed: busy || parent == null ? null : add,
              child: const Text('내 곡 추가'),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('아직 목록에 곡이 없어요.'),
              ),
            for (final item in items)
              if (itemRow(item) case final Widget row)
                Padding(
                  key: ValueKey(item['id']),
                  padding: const EdgeInsets.only(top: 8),
                  child: row,
                ),
          ],
        ),
      ),
    ),
  );
}
