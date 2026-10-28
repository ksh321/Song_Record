import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/sync/local_repository.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/editable_collection.dart';
import '../../core/widgets/folding_scaffold.dart';
import '../../core/widgets/music_view_data.dart';
import '../../core/widgets/song_discovery_sheet.dart';
import '../../core/widgets/song_row.dart';
import '../../core/widgets/ui_controls.dart';
import '../auth/auth_session.dart';
import '../charts/popular_chart.dart';
import '../search/karaoke_search.dart';
import '../search/search_intent.dart';
import '../search/song_registration_screen.dart';
import '../songs/my_song.dart';
import '../trash/trash_workflow.dart';
import 'playlist_discovery_screen.dart';
import 'playlist_library.dart';
import 'playlist_song_picker.dart';
import 'restore_candidate_song.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.library,
    required this.id,
    this.afterSave,
    this.searchLoad,
    this.chartLoad,
    this.auth,
    this.onOpenSong,
    this.trash,
    this.onOptions,
  });
  final PlaylistLibrary library;
  final String id;
  final Future<void> Function()? afterSave;
  final KaraokeLoader? searchLoad;
  final ChartLoader? chartLoad;
  final AuthController? auth;
  final void Function(String)? onOpenSong;
  final TrashActions? trash;
  final Future<void> Function(String action, Map<String, dynamic> parent)?
  onOptions;
  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  Map<String, dynamic>? parent;
  Map<String, dynamic>? orderBase;
  List<Map<String, dynamic>> items = [], songs = [];
  bool busy = false;
  bool headerFolded = false;
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
      return song == null
          ? null
          : SongRow.registered(
              song: MySong(song).view,
              onTap: widget.onOpenSong == null
                  ? null
                  : () => widget.onOpenSong!(songId as String),
            );
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
      onTap: widget.searchLoad == null ? null : () => registerCandidate(item),
    );
  }

  Future<void> registerCandidate(Map<String, dynamic> item) async {
    if (busy || parent == null || widget.searchLoad == null) return;
    final library = widget.library;
    final owner = library.repository.userId;
    final epoch = widget.auth?.accountEpoch;
    bool current() =>
        mounted &&
        identical(library, widget.library) &&
        widget.auth?.accountEpoch == epoch &&
        (widget.auth == null ||
            widget.auth!.phase == AuthPhase.ready &&
                widget.auth!.session?.userId == owner);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final number = item['candidate_number'] as String;
      final reserved = await library.repository.reservedTjSong(number);
      if (!current()) return;
      final restoration = await restoreCandidateSong(
        reserved: reserved,
        trash: widget.trash,
        isCurrent: current,
        confirm: () async =>
            await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('내 곡으로 복원할까요?'),
                content: const Text(
                  '휴지통에 있는 곡만 복원해요. 함께 삭제한 녹음은 휴지통에 그대로 남아요.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('곡만 복원'),
                  ),
                ],
              ),
            ) ??
            false,
      );
      if (restoration != CandidateRestoreResult.notReserved) {
        if (restoration == CandidateRestoreResult.restored && current()) {
          await widget.afterSave?.call();
          await reload();
        }
        return;
      }
      await library.repository.ensureTjAvailable(number);
      // Fetch a fresh verified proof, never manufacture one from the saved display snapshot.
      final matches = await widget.searchLoad!(
        KaraokeQuery(KaraokeBrand.tj, KaraokeKind.number, number),
      );
      if (!current()) return;
      final candidate = matches
          .where((c) => c.brand == KaraokeBrand.tj && c.number == number)
          .single;
      final existing = candidate.matchedSongId;
      if (existing != null) {
        final latest = (await library.load()).singleWhere(
          (p) => p['id'] == widget.id,
        );
        if (!current()) return;
        await library.linkCandidate(latest, item['id'] as String, existing)();
        await widget.afterSave?.call();
        if (current()) widget.onOpenSong?.call(existing);
      } else {
        if (!mounted) return;
        // The route owns registration from here; release the lookup lock so
        // returning/cancelling never leaves the list blocked by its refresh.
        setState(() => busy = false);
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => SongRegistrationScreen(
              candidate: candidate,
              intent: SearchIntent(
                purpose: SearchPurpose.playlist,
                playlistId: widget.id,
              ),
              prepare: (draft) {
                if (!current()) throw StateError('Account changed');
                final command = draft.prepare(library.repository);
                return () async {
                  if (!current()) throw StateError('Account changed');
                  await library.repository.save(command);
                  await widget.afterSave?.call();
                };
              },
            ),
          ),
        );
      }
      if (current()) await reload();
    } catch (failure) {
      if (current()) {
        setState(
          () => error = failure is TjTrashReservation
              ? failure.message
              : failure is TrashFailure
              ? failure.message
              : '곡을 확인하지 못했어요. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseSource() async {
    final library = widget.library, id = widget.id;
    final choice = await showSongDiscoverySheet(
      context: context,
      playlistId: id,
      playlistTitle: parent?['name'] as String?,
    );
    if (!mounted ||
        busy ||
        parent == null ||
        library != widget.library ||
        id != widget.id) {
      return;
    }
    switch (choice?.destination) {
      case SongDiscoveryDestination.mySongs:
        await add();
      case SongDiscoveryDestination.charts:
        if (widget.searchLoad != null) await discover(charts: true);
      case SongDiscoveryDestination.search:
        if (widget.searchLoad != null) await discover();
      case SongDiscoveryDestination.manual:
        await registerManual();
      default:
        break;
    }
  }

  Future<void> add() async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .85,
        child: PlaylistSongPicker(
          songs: songs.map(MySong.new).toList(),
          items: items,
        ),
      ),
    );
    if (selected == null || !mounted || parent == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.library.addRegisteredMany(
        widget.id,
        selected,
        afterEach: widget.afterSave,
      );
      await reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('목록 추가 요청 저장 완료')));
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is TjTrashReservation
              ? failure.message
              : '추가 요청을 저장하지 못했어요. 최신 목록을 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> registerManual() async {
    if (busy || parent == null) return;
    final library = widget.library;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SongRegistrationScreen(
          directEntry: true,
          intent: SearchIntent(
            purpose: SearchPurpose.playlist,
            playlistId: widget.id,
          ),
          prepare: (draft) {
            final command = draft.prepare(library.repository);
            bool songSaved = false;
            return () async {
              if (widget.auth != null &&
                  (widget.auth!.phase != AuthPhase.ready ||
                      widget.auth!.session?.userId !=
                          library.repository.userId)) {
                throw StateError('Account changed');
              }
              if (!songSaved) {
                await library.repository.save(command);
                songSaved = true;
              }
              await library.addRegisteredMany(widget.id, [
                command.entityId,
              ], afterEach: widget.afterSave);
              await widget.afterSave?.call();
            };
          },
        ),
      ),
    );
    if (mounted) await reload();
  }

  @override
  Widget build(BuildContext context) => FoldingScaffold(
    collapsed: headerFolded,
    appBar: appPageBar(
      context,
      title: Text(parent?['name'] as String? ?? '플레이리스트'),
    ),
    body: SafeArea(
      child: EditableCollection(
        key: ValueKey('${widget.library.repository.userId}:${widget.id}'),
        ids: items
            .where((item) => itemRow(item) != null)
            .map((item) => item['id'] as String)
            .toList(),
        enabled: !busy && parent != null,
        onRefresh: reload,
        onHeaderFold: (value) => setState(() => headerFolded = value),
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) Text(error!),
            if (items.isEmpty) const Text('아직 목록에 곡이 없어요.'),
          ],
        ),
        actions: (compact, reorder) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('${items.length}곡'),
            const Spacer(),
            AppReorderAction(onPressed: reorder, compact: compact),
            const SizedBox(width: 8),
            AppCompactAction(
              label: '곡 추가',
              compact: compact,
              onPressed: busy || parent == null ? null : chooseSource,
            ),
            if (widget.onOptions != null)
              PopupMenuButton<String>(
                tooltip: '플레이리스트 메뉴',
                enabled: !busy && parent != null,
                icon: const AppIcon(Icons.more_vert),
                onSelected: (action) async {
                  await widget.onOptions!(
                    action,
                    Map<String, dynamic>.from(parent!),
                  );
                  if (!mounted) return;
                  await reload();
                  if (context.mounted && parent == null) Navigator.pop(context);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('이름 변경')),
                  PopupMenuItem(value: 'icon', child: Text('아이콘 수정')),
                  PopupMenuItem(value: 'delete', child: Text('플레이리스트 삭제')),
                ],
              ),
          ],
        ),
        row: (id) => itemRow(items.firstWhere((item) => item['id'] == id))!,
        onBeginReorder: () => orderBase = Map<String, dynamic>.from(parent!),
        onReorder: reorder,
        onDelete: removeSelected,
        deleteLabel: (count) => '선택한 $count곡 목록에서 제거',
      ),
    ),
  );

  Future<void> discover({bool charts = false}) async {
    final library = widget.library, id = widget.id;
    final intent = SearchIntent(
      purpose: SearchPurpose.playlist,
      playlistId: id,
      returnRoute: '/playlists/$id',
    );
    final selected = await Navigator.of(context).push<KaraokeSelection>(
      MaterialPageRoute(
        settings: RouteSettings(
          name: '/playlists/$id/discovery',
          arguments: intent,
        ),
        builder: (_) => PlaylistDiscoveryScreen(
          initiallyCharts: charts,
          intent: intent,
          searchLoad: widget.searchLoad!,
          chartLoad: widget.chartLoad,
          auth: widget.auth,
        ),
      ),
    );
    if (!mounted ||
        selected == null ||
        !identical(selected.intent, intent) ||
        widget.library != library ||
        widget.id != id) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await library.addSelection(id, selected);
      await widget.afterSave?.call();
      await reload();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is TjTrashReservation
              ? failure.message
              : '추가 요청을 저장하지 못했어요. 최신 목록을 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> removeSelected(List<String> ids) async {
    final library = widget.library, id = widget.id;
    final epoch = widget.auth?.accountEpoch;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${ids.length}곡을 목록에서 제거할까요?'),
        content: const Text('이 목록에서만 제거해요. 내 곡과 녹음은 그대로 유지돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('제거'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      for (final itemId in ids) {
        if (!mounted ||
            library != widget.library ||
            id != widget.id ||
            widget.auth?.accountEpoch != epoch) {
          throw StateError('Account changed');
        }
        final latest = (await library.load()).singleWhere(
          (row) => row['id'] == id,
        );
        if (!mounted || widget.auth?.accountEpoch != epoch) {
          throw StateError('Account changed');
        }
        await library.removeItem(latest, itemId);
        await widget.afterSave?.call();
      }
    } finally {
      if (mounted) await reload();
    }
    return true;
  }

  Future<void> reorder(List<String> ids) async {
    if (parent == null) return;
    final original = orderBase ?? Map<String, dynamic>.from(parent!);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.library.reorder(original, ids);
      await widget.afterSave?.call();
      await reload();
    } catch (_) {
      if (mounted) setState(() => error = '순서를 저장하지 못했어요. 최신 목록을 확인해 주세요.');
      rethrow;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> removeItem(Map<String, dynamic> item) async {
    final library = widget.library, id = widget.id;
    final original = Map<String, dynamic>.from(parent!);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('목록에서 제거'),
        content: const Text('이 목록에서만 제거해요. 내 곡과 녹음은 그대로 유지돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('제거'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        !identical(library, widget.library) ||
        id != widget.id) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await library.removeItem(original, item['id'] as String);
      await widget.afterSave?.call();
      await reload();
    } catch (_) {
      if (mounted) setState(() => error = '제거하지 못했어요. 최신 목록을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
