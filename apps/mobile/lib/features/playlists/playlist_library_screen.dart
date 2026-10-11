import 'package:flutter/material.dart';

import 'playlist_library.dart';

class PlaylistLibraryScreen extends StatefulWidget {
  const PlaylistLibraryScreen({super.key, required this.library, this.onOpen});
  final PlaylistLibrary library;
  final void Function(Map<String, dynamic>)? onOpen;
  @override
  State<PlaylistLibraryScreen> createState() => _PlaylistLibraryScreenState();
}

class _PlaylistLibraryScreenState extends State<PlaylistLibraryScreen> {
  List<Map<String, dynamic>> rows = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final value = await widget.library.load();
      if (mounted) setState(() => rows = value);
    } catch (e) {
      if (mounted) setState(() => error = '목록을 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    var input = row?['name'] as String? ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(row == null ? '새 플레이리스트' : '목록 이름 변경'),
        content: TextFormField(
          initialValue: input,
          onChanged: (value) => input = value,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '목록 이름',
            helperText: '1~100자 · 같은 이름도 사용할 수 있어요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    await run(
      () => row == null
          ? widget.library.create(name)()
          : widget.library.rename(row, name)(),
    );
  }

  Future<void> remove(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('플레이리스트를 영구 삭제할까요?'),
        content: const Text(
          '이 목록과 목록 안의 구성·순서는 복원할 수 없습니다. 내 곡과 녹음은 삭제되지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('영구 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await run(() => widget.library.delete(row)());
    if (mounted && error == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('목록 삭제 전송 대기')));
    }
  }

  Future<void> run(Future<void> Function() save) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await save();
      await reload();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ArgumentError
              ? e.message.toString()
              : '목록 변경을 저장하지 못했어요. 최신 목록을 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('플레이리스트')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton.icon(
            onPressed: busy ? null : () => edit(),
            icon: const Icon(Icons.add),
            label: const Text('새 플레이리스트'),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('아직 플레이리스트가 없어요.'),
            ),
          for (final row in rows)
            Card(
              child: ListTile(
                title: Text(row['name'] as String),
                onTap: busy || widget.onOpen == null
                    ? null
                    : () => widget.onOpen!(row),
                trailing: PopupMenuButton<String>(
                  enabled: !busy,
                  onSelected: (value) =>
                      value == 'rename' ? edit(row) : remove(row),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('이름 변경')),
                    const PopupMenuItem(value: 'delete', child: Text('목록 삭제')),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
