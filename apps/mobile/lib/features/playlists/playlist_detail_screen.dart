import 'package:flutter/material.dart';

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
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final rows = await widget.library.load();
      final selected = rows.where((x) => x['id'] == widget.id).firstOrNull;
      final entries = await widget.library.items(widget.id);
      final available = await widget.library.songs();
      if (mounted) {
        setState(() {
          parent = selected;
          items = entries;
          songs = available;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '목록을 불러오지 못했어요. 다시 시도해 주세요.');
    }
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
              ListTile(
                title: Text(
                  songs
                              .where((s) => s['id'] == item['song_id'])
                              .firstOrNull?['title']
                          as String? ??
                      '등록곡',
                ),
                subtitle: Text('순서 ${(item['position'] as int) + 1}'),
              ),
          ],
        ),
      ),
    ),
  );
}
