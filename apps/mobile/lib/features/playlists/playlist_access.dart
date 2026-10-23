import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/widgets/app_icon.dart';
import '../../core/widgets/ui_controls.dart';
import '../search/karaoke_search.dart';
import 'playlist_library.dart';

/// Resolves the current account at entry; screens retain that repository lease.
class PlaylistAccess extends InheritedWidget {
  const PlaylistAccess({
    super.key,
    required this.library,
    required this.wakeSync,
    this.searchLoad,
    required super.child,
  });
  final PlaylistLibrary? Function() library;
  final VoidCallback wakeSync;
  final KaraokeLoader? searchLoad;
  @override
  bool updateShouldNotify(PlaylistAccess oldWidget) => true;
}

class AddSongToPlaylistScreen extends StatefulWidget {
  const AddSongToPlaylistScreen({
    super.key,
    required this.library,
    required this.songId,
    required this.wakeSync,
  });
  final PlaylistLibrary library;
  final String songId;
  final VoidCallback wakeSync;
  @override
  State<AddSongToPlaylistScreen> createState() => _AddSongToPlaylistState();
}

class _AddSongToPlaylistState extends State<AddSongToPlaylistScreen> {
  late final lists = widget.library.load();
  bool busy = false;
  String? error;
  Future<void> add(String id) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.library.addRegisteredMany(id, [widget.songId]);
      widget.wakeSync();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => error = '목록에 담지 못했어요. 동기화 상태를 확인한 뒤 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(context, title: const Text('플레이리스트 추가')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: lists,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('목록을 불러오지 못했어요. 다시 열어 주세요.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: AppLayout.bodyPadding,
          children: [
            if (error != null) Text(error!),
            if (snapshot.data!.isEmpty)
              const Text('먼저 플레이리스트 탭에서 목록을 만들어 주세요.'),
            for (final row in snapshot.data!)
              Card(
                child: ListTile(
                  title: Text(row['name'] as String),
                  trailing: const AppIcon(Icons.add),
                  onTap: busy ? null : () => add(row['id'] as String),
                ),
              ),
          ],
        );
      },
    ),
  );
}
