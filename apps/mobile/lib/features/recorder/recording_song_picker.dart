import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/sync/local_repository.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/feature_icon.dart';
import '../../core/widgets/song_discovery_sheet.dart';
import '../../core/widgets/ui_controls.dart';
import '../playlists/playlist_access.dart';
import '../search/karaoke_search.dart';
import '../search/search_intent.dart';
import '../search/song_registration.dart';
import '../search/song_registration_screen.dart';
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
  bool showSources = true;
  Set<String>? playlistSongIds;
  List<Map<String, dynamic>> playlistCandidates = [];
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

  Future<void> discover([SongDiscoveryDestination? requested]) async {
    final builder = widget.discoveryBuilder;
    if (!current || busy || builder == null) return;
    final destination =
        requested ??
        (await showSongDiscoverySheet(context: context))?.destination;
    if (!mounted || !current || destination == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => builder(context, destination, prepareSelection),
      ),
    );
  }

  Future<void> Function() prepareSelection(SongRegistrationDraft draft) {
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
  }

  Future<void> choosePlaylist(PlaylistAccess access) async {
    if (!current || busy) return;
    final library = access.library();
    if (library == null ||
        library.repository.userId != widget.repository.userId) {
      return;
    }
    setState(() => busy = true);
    try {
      final lists = await library.load();
      if (!mounted || !current) return;
      final id = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (lists.isEmpty) const ListTile(title: Text('아직 플레이리스트가 없어요.')),
              for (final list in lists)
                ListTile(
                  leading: const FeatureIcon(Icons.queue_music),
                  title: Text(list['name'] as String),
                  onTap: () => Navigator.pop(c, list['id'] as String),
                ),
            ],
          ),
        ),
      );
      if (id == null || !current) return;
      final items = await library.items(id);
      if (current) {
        setState(() {
          playlistSongIds = {
            for (final item in items)
              if (item['song_id'] is String) item['song_id'] as String,
          };
          playlistCandidates = items
              .where(
                (item) =>
                    item['song_id'] == null && item['candidate_brand'] == 'TJ',
              )
              .toList();
          showSources = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '플레이리스트를 확인하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseCandidate(
    Map<String, dynamic> item,
    PlaylistAccess access,
  ) async {
    if (!current || busy || access.searchLoad == null) return;
    setState(() => busy = true);
    try {
      final number = item['candidate_number'] as String;
      await widget.repository.ensureTjAvailable(number);
      final matches = await access.searchLoad!(
        KaraokeQuery(KaraokeBrand.tj, KaraokeKind.number, number),
      );
      if (!mounted || !current) return;
      final candidate = matches
          .where((c) => c.brand == KaraokeBrand.tj && c.number == number)
          .single;
      setState(() => busy = false);
      if (candidate.matchedSongId != null) {
        await select(candidate.matchedSongId!, candidate.title);
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => SongRegistrationScreen(
              candidate: candidate,
              prepare: prepareSelection,
              intent: const SearchIntent(returnRoute: '/recording/input'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = '곡을 확인하지 못했어요. 입력 대기 녹음은 보존돼 있어요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(context, title: const Text('녹음의 곡 선택')),
    body: SafeArea(
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: songs,
        builder: (context, snapshot) {
          final access = context
              .dependOnInheritedWidgetOfExactType<PlaylistAccess>();
          final available = widget.isCurrent(widget.repository);
          final candidateRows = available
              ? playlistCandidates.where((item) {
                  final snapshot = item['candidate_snapshot'] as Map;
                  final text = '${snapshot['title']} ${snapshot['artist']}'
                      .toLowerCase();
                  return text.contains(query.text.trim().toLowerCase());
                }).toList()
              : <Map<String, dynamic>>[];
          final rows = available && snapshot.hasData
              ? snapshot.data!
                    .map(MySong.new)
                    .where((song) => song.matches(query.text))
                    .where(
                      (song) =>
                          playlistSongIds == null ||
                          playlistSongIds!.contains(song.view.id.value),
                    )
                    .toList()
              : <MySong>[];
          final message = !available
              ? '계정이 변경됐어요. 돌아가 다시 열어 주세요.'
              : snapshot.hasError
              ? '내 곡을 불러오지 못했어요. 녹음 파일은 보존돼 있어요.'
              : !snapshot.hasData
              ? '내 곡 확인 중'
              : rows.isEmpty && candidateRows.isEmpty
              ? '검색 결과가 없어요.'
              : null;
          if (showSources && access != null) {
            Widget entry(
              String title,
              String subtitle,
              IconData icon,
              VoidCallback? action,
            ) => Card(
              child: ListTile(
                leading: FeatureIcon(icon),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: const AppIcon(Icons.chevron_right),
                onTap: busy || !available ? null : action,
              ),
            );
            return ListView(
              padding: AppLayout.bodyPadding,
              children: [
                if (error != null) Text(error!),
                if (available && selectedTitle != null)
                  Text('선택한 곡: $selectedTitle'),
                entry(
                  '내 곡',
                  '등록해 둔 곡에서 선택',
                  Icons.music_note_outlined,
                  () => setState(() {
                    showSources = false;
                    playlistSongIds = null;
                    playlistCandidates = [];
                  }),
                ),
                entry(
                  '플레이리스트',
                  '목록에 담아 둔 곡에서 선택',
                  Icons.queue_music,
                  () => choosePlaylist(access),
                ),
                entry(
                  '검색',
                  '노래방 곡명·가수·번호로 찾기',
                  Icons.search,
                  widget.discoveryBuilder == null
                      ? null
                      : () => discover(SongDiscoveryDestination.search),
                ),
                entry(
                  '직접 등록',
                  '곡명과 가수를 직접 입력',
                  Icons.edit_outlined,
                  widget.discoveryBuilder == null
                      ? null
                      : () => discover(SongDiscoveryDestination.manual),
                ),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('입력 대기로 돌아가기'),
                ),
              ],
            );
          }
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                sliver: SliverList.list(
                  children: [
                    if (access != null)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => showSources = true),
                        child: const Text('다른 곳에서 선택'),
                      ),
                    const Text('녹음 파일은 입력 대기로 보관돼요. 내 곡을 검색하거나 새 곡을 찾아 선택하세요.'),
                    TextField(
                      controller: query,
                      decoration: const InputDecoration(
                        labelText: '내 곡명 또는 가수 검색',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (available && selectedTitle != null)
                      Text('선택한 곡: $selectedTitle'),
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
                  trailing: const AppIcon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () => select(rows[i].view.id.value, rows[i].view.title),
                ),
              ),
              if (access != null)
                SliverList.list(
                  children: [
                    for (final item in candidateRows)
                      ListTile(
                        title: Text(
                          (item['candidate_snapshot'] as Map)['title']
                              as String,
                        ),
                        subtitle: Text(
                          '${(item['candidate_snapshot'] as Map)['artist']} · TJ ${item['candidate_number']}',
                        ),
                        trailing: const AppIcon(Icons.chevron_right),
                        onTap: busy || !available
                            ? null
                            : () => chooseCandidate(item, access),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    ),
  );
}
