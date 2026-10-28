import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/domain/identifiers.dart';
import '../../core/domain/song_types.dart';
import '../../core/theme/app_appearance.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/detail_information_card.dart';
import '../../core/widgets/music_view_data.dart';
import '../../core/widgets/recording_roles_card.dart';
import '../../core/widgets/recording_row.dart';
import '../../core/widgets/scroll_to_top_button.dart';
import '../../core/widgets/selection_sheet.dart';
import '../../core/widgets/song_badges.dart';
import '../../core/widgets/song_row.dart';
import '../../core/widgets/ui_controls.dart';
import '../../routing/app_routes.dart';
import '../../routing/tab_navigation.dart';
import '../auth/auth_session.dart';
import '../recorder/recording_audio_panel.dart';
import '../recorder/recording_navigation.dart';
import '../trash/trash_screens.dart';
import '../trash/trash_workflow.dart';
import 'my_song_detail.dart';
import 'song_action_entry.dart';
import 'song_edit.dart';
import 'song_edit_screen.dart';
import 'song_representative.dart';

typedef SongDetailWatch = Stream<MySongDetail> Function();

class SongDetailScreen extends StatefulWidget {
  const SongDetailScreen({
    required this.watch,
    this.auth,
    this.recordingId,
    this.selectionPreview = false,
    this.prepareEdit,
    this.prepareRepresentative,
    this.trash,
    super.key,
  });
  final SongDetailWatch watch;
  final AuthController? auth;
  final String? recordingId;
  final bool selectionPreview;
  final SongEditPreparer? prepareEdit;
  final RepresentativePreparer? prepareRepresentative;
  final TrashActions? trash;
  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> {
  StreamSubscription<MySongDetail>? subscription;
  MySongDetail? detail;
  Object? error;
  bool changedAccount = false;
  late final String scope = tag();
  int generation = 0;
  bool choosing = false, savingSuitability = false, confirmingSelection = false;
  String? representativeError;
  Future<void> Function()? representativeCommand;
  String tag() =>
      '${widget.auth?.phase}:${widget.auth?.session?.userId}:${widget.auth?.session?.deviceId}';
  @override
  void initState() {
    super.initState();
    widget.auth?.addListener(authChanged);
    bind();
  }

  void authChanged() {
    if (tag() != scope) {
      ++generation;
      unawaited(subscription?.cancel());
      setState(() {
        changedAccount = true;
        detail = null;
        error = null;
      });
    }
  }

  void bind() {
    if (changedAccount || tag() != scope) return;
    final request = ++generation;
    unawaited(subscription?.cancel());
    setState(() {
      detail = null;
      error = null;
    });
    try {
      subscription = widget.watch().listen(
        (value) {
          if (!mounted || request != generation || tag() != scope) return;
          setState(() {
            detail = value;
            error = null;
          });
        },
        onError: (Object failure) {
          if (!mounted || request != generation || tag() != scope) return;
          setState(() {
            detail = null;
            error = failure;
          });
        },
      );
    } catch (failure) {
      error = failure;
    }
  }

  @override
  void didUpdateWidget(covariant SongDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      oldWidget.auth?.removeListener(authChanged);
      widget.auth?.addListener(authChanged);
      authChanged();
    }
    if (oldWidget.watch != widget.watch && !changedAccount) bind();
  }

  @override
  void dispose() {
    ++generation;
    widget.auth?.removeListener(authChanged);
    unawaited(subscription?.cancel());
    super.dispose();
  }

  void openRecording(RecordingId id) {
    if (!mounted || changedAccount || tag() != scope) return;
    final build = context
        .getInheritedWidgetOfExactType<RecordingAudioAccess>()
        ?.detailsBuilder;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => build != null
            ? build(context, id.value)
            : SongDetailScreen(
                watch: widget.watch,
                auth: widget.auth,
                recordingId: id.value,
              ),
      ),
    );
  }

  void playRecording(RecordingViewData recording) => openRecordingPlayback(
    context,
    recording,
    isCurrent: () => mounted && !changedAccount && tag() == scope,
    onDetails: () => openRecording(recording.id),
  );

  Future<void> chooseRepresentative(MySongDetail value) async {
    if (choosing || changedAccount || widget.prepareRepresentative == null) {
      return;
    }
    if (representativeCommand == null) {
      final result = await showSelectionSheet<String?>(
        context: context,
        title: '대표 녹음 선택',
        showDividers: true,
        onPreview: (id) async {
          if (!mounted || changedAccount || tag() != scope) return false;
          if (id == null) return true;
          return await Navigator.of(context, rootNavigator: true).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SongDetailScreen(
                    watch: widget.watch,
                    auth: widget.auth,
                    recordingId: id,
                    selectionPreview: true,
                  ),
                ),
              ) ==
              true;
        },
        selected: value.roles.representative?.value,
        options: [
          for (final r in value.recordings)
            SelectionOption(
              r.id.value,
              r.snapshot.title,
              description:
                  '${r.dateLabel} · ${r.durationLabel} · ${formatRecordingTier(r.tier)}',
            ),
          const SelectionOption(null, '대표 해제'),
        ],
      );
      if (!mounted || result == null || changedAccount || tag() != scope) {
        return;
      }
      final current = detail;
      if (current == null ||
          current.song == null ||
          current.song!.view.id != value.song!.view.id) {
        return;
      }
      try {
        representativeCommand = widget.prepareRepresentative!(
          current,
          result.value == null ? null : RecordingId(result.value!),
        );
      } catch (_) {
        setState(() => representativeError = '대표 지정 값을 확인하지 못했어요. 다시 열어 주세요.');
        return;
      }
    }
    setState(() {
      choosing = true;
      representativeError = null;
    });
    try {
      await representativeCommand!();
      if (mounted && !changedAccount) {
        setState(() => representativeCommand = null);
      }
    } catch (_) {
      if (mounted && !changedAccount) {
        setState(
          () => representativeError = '대표를 저장하지 못했어요. 같은 변경을 재시도하거나 다시 열어 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.selectionPreview
              ? '대표 녹음 확인'
              : widget.recordingId == null
              ? '곡 상세'
              : '녹음 정보',
          style: widget.selectionPreview ? const TextStyle(fontSize: 18) : null,
        ),
        actions: [
          const ThemeToggle(),
          IconButton(
            tooltip: '설정',
            icon: const AppIcon(Icons.settings_outlined, size: 22),
            onPressed: () {
              final tabs = TabNavigation.maybeOf(context);
              if (tabs != null) {
                tabs.openSettings();
              } else {
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).pushNamed(AppRoutes.settings);
              }
            },
          ),
          const SizedBox(width: 20),
        ],
      ),
      bottomNavigationBar: widget.selectionPreview
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed:
                      !confirmingSelection &&
                          !changedAccount &&
                          tag() == scope &&
                          value != null &&
                          value.song != null &&
                          value.recordings.any(
                            (r) => r.id.value == widget.recordingId,
                          )
                      ? () {
                          setState(() => confirmingSelection = true);
                          Navigator.of(context).pop(true);
                        }
                      : null,
                  child: const Text('이 녹음을 대표로 지정'),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: changedAccount
            ? const ContentState(
                phase: ContentPhase.waiting,
                title: '계정이 변경됐어요. 내 곡 목록에서 다시 열어 주세요.',
              )
            : error != null
            ? ContentState(
                phase: ContentPhase.error,
                title: '곡 정보를 불러오지 못했어요.',
                onRetry: bind,
              )
            : value == null
            ? const ContentState(
                phase: ContentPhase.loading,
                title: '곡 정보를 불러오고 있어요.',
              )
            : value.song == null
            ? const ContentState(
                phase: ContentPhase.empty,
                title: '현재 계정의 활성 곡을 찾을 수 없어요.',
              )
            : widget.recordingId != null
            ? recording(value)
            : song(value),
      ),
    );
  }

  Widget song(MySongDetail detail) {
    final view = detail.song!.view;
    final value = detail;
    return ScrollToTopView(
      builder: (scroll) => ListView(
        controller: scroll,
        padding: AppLayout.bodyPadding,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            child: Column(
              children: [
                Text(
                  view.title,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${view.artist} · ${view.tjNumber == null ? '직접 등록' : 'TJ ${view.tjNumber!.value}'}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.8,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.recordingId == null &&
                    value.song != null &&
                    !changedAccount)
                  PopupMenuButton<String>(
                    tooltip: '곡 메뉴',
                    icon: const AppIcon(Icons.more_vert),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'playlist',
                        child: Text('플레이리스트 추가'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('곡 삭제')),
                    ],
                    onSelected: (action) => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) =>
                            action == 'delete' && widget.trash != null
                            ? DeleteScreen(
                                actions: widget.trash!,
                                id: value.song!.view.id.value,
                                title: value.song!.view.title,
                                auth: widget.auth,
                              )
                            : SongActionEntry(
                                action: action == 'delete'
                                    ? SongAction.delete
                                    : SongAction.playlistAdd,
                                detail: value,
                                auth: widget.auth,
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DetailInformationCard(
            title: '곡 정보',
            fields: [
              ('버전', formatVersionCode(view.version)),
              (
                '대표 키',
                view.musicalKey == null
                    ? '미정'
                    : formatMusicalKey(view.musicalKey!),
              ),
              ('곡 티어', formatSongTier(view.tier)),
            ],
            action: widget.prepareEdit == null
                ? null
                : TextButton.icon(
                    icon: const AppIcon(Icons.edit_outlined, size: 14),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => SongEditScreen(
                          draft: SongEditDraft(detail),
                          prepare: widget.prepareEdit!,
                          auth: widget.auth,
                        ),
                      ),
                    ),
                    label: const Text('곡 수정'),
                  ),
          ),
          SongSuitabilityChoice(
            value: view.isSuitable,
            onChanged: savingSuitability || widget.prepareEdit == null
                ? null
                : (v) async {
                    if (changedAccount || tag() != scope) return;
                    final draft = SongEditDraft(detail)..isSuitable = v;
                    final command = widget.prepareEdit!(draft);
                    setState(() => savingSuitability = true);
                    try {
                      await command();
                    } catch (_) {
                      if (mounted && tag() == scope) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('표시를 저장하지 못했어요. 다시 시도해 주세요.'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => savingSuitability = false);
                    }
                  },
          ),
          AppPanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '메모',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  view.note.isEmpty ? '아직 작성하지 않았어요.' : view.note,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          RecordingRolesCard(
            songId: view.id,
            selection: detail.roles,
            recordings: {for (final r in detail.recordings) r.id: r},
            onChooseRepresentative:
                widget.prepareRepresentative == null || choosing
                ? null
                : () => chooseRepresentative(detail),
            onOpenRecording: openRecording,
            onPlayRecording: (id) =>
                playRecording(detail.recordings.firstWhere((r) => r.id == id)),
          ),
          if (representativeError != null) ...[
            Text(representativeError!),
            TextButton(
              onPressed: choosing ? null : () => chooseRepresentative(detail),
              child: const Text('같은 대표 변경 다시 저장'),
            ),
          ],
          if (choosing) const Text('대표 저장 중'),
          const SizedBox(height: AppSpacing.lg),
          Text('연결 녹음 (${detail.recordings.length})'),
          if (detail.recordings.isEmpty) const Text('연결된 녹음이 없어요.'),
          for (final r in detail.recordings)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: RecordingRow(
                key: ValueKey('linked-recording-${r.id.value}'),
                recording: r,
                onPlay: () => playRecording(r),
                onTap: () => openRecording(r.id),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget recording(MySongDetail detail) {
    RecordingViewData? view;
    for (final r in detail.recordings) {
      if (r.id.value == widget.recordingId) view = r;
    }
    if (view == null) {
      return const ContentState(
        phase: ContentPhase.empty,
        title: '이 곡에 연결된 활성 녹음을 찾을 수 없어요.',
      );
    }
    final snapshot = view.snapshot;
    return ListView(
      padding: AppLayout.bodyPadding,
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                snapshot.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(snapshot.artist),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(formatVersionCode(snapshot.version)),
                  MusicalKeyBadge(value: snapshot.key),
                  Text('녹음 티어: ${formatRecordingTier(view.tier)}'),
                ],
              ),
              const SizedBox(height: 14),
              Text(view.dateLabel),
              Text(view.durationLabel),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppPanel(child: RecordingAudioPanel(view.id.value, compact: true)),
        const SizedBox(height: 14),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('녹음 당시 메모'),
              const SizedBox(height: 8),
              Text(snapshot.note.isEmpty ? '작성한 메모가 없어요.' : snapshot.note),
            ],
          ),
        ),
      ],
    );
  }
}
