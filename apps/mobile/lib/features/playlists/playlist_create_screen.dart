import 'package:flutter/material.dart';

import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_page_bar.dart';

class PlaylistCreateScreen extends StatefulWidget {
  const PlaylistCreateScreen({
    required this.icons,
    required this.labels,
    super.key,
  });
  final Map<String, IconData> icons;
  final Map<String, String> labels;
  @override
  State<PlaylistCreateScreen> createState() => _PlaylistCreateScreenState();
}

class _PlaylistCreateScreenState extends State<PlaylistCreateScreen> {
  String name = '', icon = 'music';
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(context, title: const Text('새 플레이리스트')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                if (name.trim().isEmpty) {
                  setState(() => error = '플레이리스트 이름을 입력해 주세요.');
                  return;
                }
                Navigator.pop(context, (name: name.trim(), icon: icon));
              },
              child: const Text('만들기'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('플레이리스트 이름'),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (value) => name = value,
                  maxLength: 100,
                  decoration: InputDecoration(
                    counterText: '',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 32),
                const Text('아이콘'),
                const SizedBox(height: 8),
                Text(
                  '선택하지 않으면 음표로 만들어요',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in widget.icons.entries)
                        SizedBox(
                          width: (constraints.maxWidth - 16) / 3,
                          height: 76,
                          child: OutlinedButton(
                            onPressed: () => setState(() => icon = entry.key),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(4),
                              side: BorderSide(
                                color: icon == entry.key
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AppIcon(
                                  entry.value,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 24,
                                ),
                                Text(
                                  widget.labels[entry.key] ?? '',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
