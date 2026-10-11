import 'package:flutter/material.dart';

import '../../core/widgets/song_row.dart';
import '../songs/my_song.dart';

/// Membership is scoped to the destination playlist, including TJ candidates.
bool playlistContainsSong(List<Map<String, dynamic>> items, MySong song) =>
    items.any(
      (item) =>
          item['song_id'] == song.view.id.value ||
          item['entry_key'] ==
              (song.view.tjNumber == null
                  ? 'manual:${song.view.id.value}'
                  : 'tj:${song.view.tjNumber!.value}'),
    );

class PlaylistSongPicker extends StatefulWidget {
  const PlaylistSongPicker({
    super.key,
    required this.songs,
    required this.items,
  });
  final List<MySong> songs;
  final List<Map<String, dynamic>> items;
  @override
  State<PlaylistSongPicker> createState() => _PlaylistSongPickerState();
}

class _PlaylistSongPickerState extends State<PlaylistSongPicker> {
  final selected = <String>{};
  String query = '';
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        children: [
          const Text('내 곡 다중 선택'),
        const Text('한 번에 100곡까지 선택할 수 있어요.'),
          TextField(
            decoration: const InputDecoration(labelText: '내 곡 검색'),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final song in widget.songs.where((s) => s.matches(query)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected.contains(song.view.id.value),
                          onChanged: playlistContainsSong(widget.items, song)
                              ? null
                              : (checked) => setState(() {
                                  if (checked == true) {
                                    selected.add(song.view.id.value);
                                  } else {
                                    selected.remove(song.view.id.value);
                                  }
                                }),
                        ),
                        Expanded(
                          child: SongRow.registered(
                            song: song.view,
                            alreadyAdded: playlistContainsSong(
                              widget.items,
                              song,
                            ),
                            onTap: () => setState(() {
                              if (!selected.add(song.view.id.value)) {
                                selected.remove(song.view.id.value);
                              }
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!widget.songs.any((s) => s.matches(query)))
                  const Text('검색 결과가 없어요.'),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, selected.toList()),
                child: Text('${selected.length}곡 추가'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
