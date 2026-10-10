import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/domain/identifiers.dart';
import '../../core/domain/song_types.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/music_view_data.dart';
import '../../core/widgets/recording_roles_card.dart';
import '../../core/widgets/recording_row.dart';
import '../../core/widgets/selection_sheet.dart';
import '../auth/auth_session.dart';
import 'my_song_detail.dart';
import 'song_edit.dart';
import 'song_edit_screen.dart';
import 'song_representative.dart';

typedef SongDetailWatch = Stream<MySongDetail> Function();

class SongDetailScreen extends StatefulWidget {
  const SongDetailScreen({
    required this.watch,
    this.auth,
    this.recordingId,
    this.prepareEdit,
    this.prepareRepresentative,
    super.key,
  });
  final SongDetailWatch watch;
  final AuthController? auth;
  final String? recordingId;
  final SongEditPreparer? prepareEdit;
  final RepresentativePreparer? prepareRepresentative;
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
  bool choosing = false;
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

  void openRecording(RecordingId id) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SongDetailScreen(
        watch: widget.watch,
        auth: widget.auth,
        recordingId: id.value,
      ),
    ),
  );

  Future<void> chooseRepresentative(MySongDetail value) async {
    if (choosing || changedAccount || widget.prepareRepresentative == null) {
      return;
    }
    if (representativeCommand == null) {
      final result = await showSelectionSheet<String?>(
        context: context,
        title: '대표 녹음 선택',
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
      try {
        representativeCommand = widget.prepareRepresentative!(
          value,
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
        title: Text(widget.recordingId == null ? '곡 상세' : '녹음 정보'),
      ),
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
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(view.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(view.artist),
        if (widget.prepareEdit != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SongEditScreen(
                    draft: SongEditDraft(detail),
                    prepare: widget.prepareEdit!,
                    auth: widget.auth,
                  ),
                ),
              ),
              child: const Text('곡 수정'),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(formatVersionCode(view.version)),
        Text(
          '대표 키: ${view.musicalKey == null ? '미정' : formatMusicalKey(view.musicalKey!)}',
        ),
        Text('곡 티어: ${formatSongTier(view.tier)}'),
        Text(view.tjNumber == null ? 'TJ 번호 없음' : 'TJ ${view.tjNumber!.value}'),
        const SizedBox(height: AppSpacing.md),
        const Text('아쉬운 점'),
        Text(view.note.isEmpty ? '작성한 아쉬운 점이 없어요.' : view.note),
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
              recording: r,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SongDetailScreen(
                    watch: widget.watch,
                    auth: widget.auth,
                    recordingId: r.id.value,
                  ),
                ),
              ),
            ),
          ),
      ],
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(snapshot.title, style: Theme.of(context).textTheme.headlineSmall),
        Text(snapshot.artist),
        Text(formatVersionCode(snapshot.version)),
        Text(formatMusicalKey(snapshot.key)),
        Text('녹음 티어: ${formatRecordingTier(view.tier)}'),
        Text(view.dateLabel),
        Text(view.durationLabel),
        Text(view.fileAvailability.label),
        const SizedBox(height: AppSpacing.md),
        const Text('녹음 당시 메모'),
        Text(snapshot.note.isEmpty ? '작성한 메모가 없어요.' : snapshot.note),
      ],
    );
  }
}
