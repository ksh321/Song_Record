import 'package:flutter/material.dart';

class PlaylistOrderPicker extends StatefulWidget {
  const PlaylistOrderPicker({
    super.key,
    required this.items,
    required this.titles,
  });
  final List<Map<String, dynamic>> items;
  final Map<String, String> titles;
  @override
  State<PlaylistOrderPicker> createState() => _PlaylistOrderPickerState();
}

class _PlaylistOrderPickerState extends State<PlaylistOrderPicker> {
  late final ids = widget.items.map((i) => i['id'] as String).toList();
  void move(int from, int to) => setState(() {
    ids.insert(to, ids.removeAt(from));
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('목록 순서 변경'),
          const Text('위·아래 버튼으로 순서를 바꾸고 저장해 주세요.'),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < ids.length; i++)
                  ListTile(
                    key: ValueKey(ids[i]),
                    title: Text(widget.titles[ids[i]] ?? '목록 항목'),
                    leading: Text('${i + 1}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '${i + 1}번 위로',
                          onPressed: i == 0 ? null : () => move(i, i - 1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: '${i + 1}번 아래로',
                          onPressed: i == ids.length - 1
                              ? null
                              : () => move(i, i + 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                      ],
                    ),
                  ),
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
                onPressed: () => Navigator.pop(context, ids),
                child: const Text('순서 저장'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
