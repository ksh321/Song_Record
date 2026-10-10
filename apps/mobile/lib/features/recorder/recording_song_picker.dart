import 'package:flutter/material.dart';

import '../../core/sync/local_repository.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/song_discovery_sheet.dart';
import '../search/song_registration.dart';
import '../songs/my_song.dart';

typedef RecordingDiscoveryBuilder = Widget Function(
  BuildContext context,
  SongDiscoveryDestination destination,
  SongRegistrationPreparer prepare,
);

class RecordingSongPicker extends StatefulWidget {
  const RecordingSongPicker({
    required this.recordingId,
    required this.repository,
    required this.isCurrent,
    this.discoveryBuilder,
    this.watchSongs,
    this.wakeSync,
    super.key,
  });
  final String recordingId;
  final LocalRepository repository;
  final bool Function(LocalRepository) isCurrent;
  final RecordingDiscoveryBuilder? discoveryBuilder;
  final Stream<List<Map<String, dynamic>>> Function()? watchSongs;
  final VoidCallback? wakeSync;
  @override
  State<RecordingSongPicker> createState() => _RecordingSongPickerState();
}

class _RecordingSongPickerState extends State<RecordingSongPicker> {
  final query = TextEditingController();
  late final songs =
      widget.watchSongs?.call() ?? widget.repository.watchActiveSongs();
  String? selectedTitle, error;
  bool busy = false;
  bool get current => mounted && widget.isCurrent(widget.repository);
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> select(String id, String title) async {
    if (busy || !current) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.selectPendingRecordingSong(
        widget.recordingId,
        id,
      );
      if (current) setState(() => selectedTitle = title);
    } catch (_) {
      if (mounted) setState(() => error = '곡을 선택하지 못했어요. 입력 대기 녹음은 보존돼 있어요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> discover() async {
    final builder = widget.discoveryBuilder;
    if (!current || busy || builder == null) return;
    final destination = await showSongDiscoverySheet(context: context);
    if (!mounted || !current || destination == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            builder(context, destination.destination, (draft) {
              if (!current) throw StateError('Account changed');
              final existing = draft.candidate?.matchedSongId;
              if (existing != null) {
                return () async {
                  if (!current) throw StateError('Account changed');
                  await widget.repository.selectPendingRecordingSong(
                    widget.recordingId,
                    existing,
                  );
                  if (current) setState(() => selectedTitle = draft.title);
                };
              }
              final command = draft.prepare(widget.repository);
              return () async {
                if (!current) throw StateError('Account changed');
                await widget.repository.save(command);
                if (!current) throw StateError('Account changed');
                await widget.repository.selectPendingRecordingSong(
                  widget.recordingId,
                  command.entityId,
                );
                if (current) setState(() => selectedTitle = draft.title);
                widget.wakeSync?.call();
              };
            }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('녹음의 곡 선택')),
    body: SafeArea(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: songs,
        builder: (context, snapshot) {
          final available = widget.isCurrent(widget.repository);
          final rows = available && snapshot.hasData
              ? snapshot.data!
                    .map(MySong.new)
                    .where((song) => song.matches(query.text))
                    .toList()
              : <MySong>[];
          final message = !available
              ? '계정이 변경됐어요. 돌아가 다시 열어 주세요.'
              : snapshot.hasError
              ? '내 곡을 불러오지 못했어요. 녹음 파일은 보존돼 있어요.'
              : !snapshot.hasData
              ? '내 곡 확인 중'
              : rows.isEmpty
              ? '검색 결과가 없어요.'
              : null;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                sliver: SliverList.list(
                  children: [
                    const Text('녹음 파일은 입력 대기로 보관돼요. 내 곡을 검색하거나 새 곡을 찾아 선택하세요.'),
                    TextField(
                      controller: query,
                      decoration: const InputDecoration(
                        labelText: '내 곡명 또는 가수 검색',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (selectedTitle != null) Text('선택한 곡: $selectedTitle'),
                    if (error != null) Text(error!),
                    FilledButton(
                      onPressed:
                          busy || !available || widget.discoveryBuilder == null
                          ? null
                          : discover,
                      child: const Text('새 곡 찾기'),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: const Text('입력 대기로 돌아가기'),
                    ),
                    if (message != null) Text(message),
                  ],
                ),
              ),
              SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(rows[i].view.title),
                  subtitle: Text(rows[i].view.artist),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () => select(rows[i].view.id.value, rows[i].view.title),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
