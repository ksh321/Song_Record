import 'package:flutter/material.dart';

import '../../core/sync/local_repository.dart';
import '../../core/theme/app_tokens.dart';
import '../songs/my_song.dart';

class RecordingRelinkScreen extends StatefulWidget {
  const RecordingRelinkScreen({
    required this.recording,
    required this.revision,
    required this.repository,
    required this.isCurrent,
    this.wakeSync,
    this.watchSongs,
    super.key,
  });
  final Map<String, dynamic> recording;
  final int revision;
  final LocalRepository repository;
  final bool Function(LocalRepository) isCurrent;
  final VoidCallback? wakeSync;
  final Stream<List<Map<String, dynamic>>> Function()? watchSongs;
  @override
  State<RecordingRelinkScreen> createState() => _RecordingRelinkScreenState();
}

class _RecordingRelinkScreenState extends State<RecordingRelinkScreen> {
  final query = TextEditingController();
  late final songs =
      widget.watchSongs?.call() ?? widget.repository.watchActiveSongs();
  Future<void> Function()? command;
  bool busy = false;
  String? error;
  bool get current => mounted && widget.isCurrent(widget.repository);
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> select(String? id, String title) async {
    if (!current || busy || command != null) return;
    final changed = id != widget.recording['song_id'];
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(id == null ? '미연결로 변경' : '이 곡으로 연결'),
        content: Text(
          '$title\n연결만 변경하고 녹음 당시 제목·가수·키·버전·메모는 유지해요. 연결 변경 번호는 ${widget.recording['link_revision'] ?? 1}에서 ${(widget.recording['link_revision'] as int? ?? 1) + (changed ? 1 : 0)}로 바뀌어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('연결 저장'),
          ),
        ],
      ),
    );
    if (!current || yes != true) return;
    command = widget.repository.prepareRecordingRelink(
      widget.recording,
      widget.revision,
      id,
    );
    await save();
  }

  Future<void> save() async {
    if (!current || busy || command == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await command!();
      if (!mounted || !widget.isCurrent(widget.repository)) return;
      widget.wakeSync?.call();
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = '연결을 저장하지 못했어요. 녹음 정보와 파일은 유지돼요. 다시 저장하거나 돌아가 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('녹음의 곡 연결 변경')),
    body: SafeArea(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: songs,
        builder: (context, snapshot) {
          final rows = !current || !snapshot.hasData
              ? <MySong>[]
              : snapshot.data!
                    .map(MySong.new)
                    .where((s) => s.matches(query.text))
                    .toList();
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const Text(
                '곡을 검색해 선택한 뒤 연결 저장을 눌러 주세요. 녹음 당시 정보는 새 곡 정보로 덮어쓰지 않아요.',
              ),
              TextField(
                controller: query,
                enabled: current && !busy && command == null,
                decoration: const InputDecoration(labelText: '내 곡명 또는 가수 검색'),
                onChanged: (_) => setState(() {}),
              ),
              if (!current) const Text('계정이 변경됐어요. 다시 열어 주세요.'),
              if (snapshot.hasError)
                const Text('내 곡을 확인하지 못했어요. 녹음 정보와 파일은 유지돼요.'),
              if (current && snapshot.hasData && rows.isEmpty)
                const Text('검색 결과가 없어요.'),
              if (error != null) Text(error!),
              if (command != null)
                FilledButton(
                  onPressed: busy || !current ? null : save,
                  child: const Text('같은 연결 다시 저장'),
                ),
              for (final song in rows)
                ListTile(
                  title: Text(song.view.title),
                  subtitle: Text(song.view.artist),
                  onTap: busy || command != null || !current
                      ? null
                      : () => select(song.view.id.value, song.view.title),
                ),
              if (widget.recording['song_id'] != null)
                TextButton(
                  onPressed: busy || command != null || !current
                      ? null
                      : () => select(null, '미연결 녹음으로 보관해요.'),
                  child: const Text('곡 연결 해제'),
                ),
            ],
          );
        },
      ),
    ),
  );
}
