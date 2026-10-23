import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/sync/local_repository.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/feature_icon.dart';
import '../../core/widgets/music_view_data.dart';
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
import 'playlist_order_picker.dart';
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
  });
  final PlaylistLibrary library;
  final String id;
  final Future<void> Function()? afterSave;
  final KaraokeLoader? searchLoad;
  final ChartLoader? chartLoad;
  final AuthController? auth;
  final void Function(String)? onOpenSong;
  final TrashActions? trash;
  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  Map<String, dynamic>? parent;
  List<Map<String, dynamic>> items = [], songs = [];
  bool busy = false;
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
    final menu = PopupMenuButton<String>(
      tooltip: '곡 메뉴',
      enabled: !busy && parent != null,
      icon: const AppIcon(Icons.more_vert),
      onSelected: (value) =>
          value == 'register' ? registerCandidate(item) : removeItem(item),
      itemBuilder: (_) => [
        if (item['song_id'] == null && widget.searchLoad != null)
          const PopupMenuItem(value: 'register', child: Text('내 곡 등록')),
        const PopupMenuItem(value: 'remove', child: Text('목록에서 제거')),
      ],
    );
    final songId = item['song_id'];
    if (songId != null) {
      final song = songs.where((s) => s['id'] == songId).firstOrNull;
      // A linked trashed/missing song must not reappear as a catalog candidate.
      return song == null
          ? null
          : SongRow.registered(
              song: MySong(song).view,
              trailingAction: menu,
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
      trailingAction: menu,
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
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('곡 추가')),
            ListTile(
              leading: const FeatureIcon(Icons.music_note_outlined),
              title: const Text('내 곡에서 선택'),
              onTap: () => Navigator.pop(context, 'songs'),
            ),
            if (widget.searchLoad != null)
              ListTile(
                leading: const FeatureIcon(Icons.search),
                title: const Text('검색·차트에서 추가'),
                onTap: () => Navigator.pop(context, 'discover'),
              ),
            ListTile(
              leading: const FeatureIcon(Icons.edit_outlined),
              title: const Text('직접 등록'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || busy || parent == null) return;
    switch (action) {
      case 'songs':
        await add();
      case 'discover':
        await discover();
      case 'manual':
        await registerManual();
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(parent?['name'] as String? ?? '플레이리스트')),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: AppLayout.bodyPadding,
          children: [
            if (error != null) Text(error!),
            Row(
              children: [
                Text('${items.length}곡'),
                const Spacer(),
                TextButton(
                  onPressed: busy || parent == null || items.length < 2
                      ? null
                      : reorder,
                  child: const Text('순서 변경'),
                ),
                AppCompactAction(
                  label: '곡 추가',
                  onPressed: busy || parent == null ? null : chooseSource,
                ),
              ],
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('아직 목록에 곡이 없어요.'),
              ),
            for (final item in items)
              if (itemRow(item) case final Widget row)
                Padding(
                  key: ValueKey(item['id']),
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    onLongPress: busy || parent == null || items.length < 2
                        ? null
                        : reorder,
                    child: row,
                  ),
                ),
          ],
        ),
      ),
    ),
  );

  Future<void> discover() async {
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

  Future<void> reorder() async {
    final library = widget.library, playlistId = widget.id;
    final original = Map<String, dynamic>.from(parent!);
    final titles = <String, String>{};
    for (final item in items) {
      final song = songs.where((s) => s['id'] == item['song_id']).firstOrNull;
      titles[item['id'] as String] =
          (song?['title'] ??
                  (item['candidate_snapshot'] as Map?)?['title'] ??
                  '목록 항목')
              as String;
    }
    final ids = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .8,
        child: PlaylistOrderPicker(items: items, titles: titles),
      ),
    );
    if (!mounted ||
        ids == null ||
        !identical(library, widget.library) ||
        playlistId != widget.id) {
      return;
    }
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
