import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/domain/song_types.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/musical_key_picker.dart';
import '../../core/widgets/song_badges.dart';
import '../../core/widgets/tier_picker.dart';
import '../../core/widgets/ui_controls.dart';
import '../../core/widgets/version_picker.dart';
import '../auth/auth_session.dart';
import 'song_edit.dart';

class SongEditScreen extends StatefulWidget {
  const SongEditScreen({
    required this.draft,
    required this.prepare,
    this.auth,
    this.noteOnly = false,
    super.key,
  });
  final bool noteOnly;
  final SongEditDraft draft;
  final SongEditPreparer prepare;
  final AuthController? auth;
  @override
  State<SongEditScreen> createState() => _SongEditScreenState();
}

class _SongEditScreenState extends State<SongEditScreen> {
  late final title = TextEditingController(text: widget.draft.title);
  late final artist = TextEditingController(text: widget.draft.artist);
  late final note = TextEditingController(text: widget.draft.note);
  late final scope = tag();
  Future<void> Function()? command;
  bool busy = false, revoked = false;
  String? error;
  String tag() =>
      '${widget.auth?.phase}:${widget.auth?.session?.userId}:${widget.auth?.session?.deviceId}';
  bool get editable => !busy && !revoked && command == null;
  @override
  void initState() {
    super.initState();
    widget.auth?.addListener(accountChanged);
  }

  void accountChanged() {
    if (tag() != scope && mounted) {
      setState(() {
        revoked = true;
        error = null;
      });
    }
  }

  @override
  void dispose() {
    widget.auth?.removeListener(accountChanged);
    title.dispose();
    artist.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || revoked || tag() != scope) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (command == null) {
        widget.draft.title = title.text;
        widget.draft.artist = artist.text;
        widget.draft.note = note.text;
        command = widget.prepare(widget.draft);
      }
      await command!();
      if (mounted && !revoked && tag() == scope) {
        Navigator.of(context).pop(true);
      }
    } catch (failure) {
      if (mounted && !revoked) {
        setState(
          () => error = failure is ArgumentError
              ? '곡명·가수는 1~200자, 메모은 2,000자 이내로 입력해 주세요.'
              : '저장하지 못했어요. 같은 변경을 다시 저장하거나, 원본이 바뀌었다면 취소하고 다시 열어 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: appPageBar(
        context,
        title: Text(widget.noteOnly ? '메모 수정' : '곡 정보 수정'),
        leading: IconButton(
          tooltip: '취소',
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          icon: const AppIcon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: revoked
            ? const ContentState(
                phase: ContentPhase.waiting,
                title: '계정이 변경됐어요. 편집을 닫고 다시 열어 주세요.',
              )
            : ListView(
                padding: AppLayout.bodyPadding,
                children: [
                  AppPanel(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        if (!widget.noteOnly) ...[
                          AppLabeledField(
                            label: '곡명',
                            controller: title,
                            enabled: editable,
                          ),
                          const SizedBox(height: 14),
                          AppLabeledField(
                            label: '가수',
                            controller: artist,
                            enabled: editable,
                          ),
                          const SizedBox(height: 14),
                        ],
                        AppLabeledField(
                          label: '메모',
                          controller: note,
                          enabled: editable,
                          minLines: 4,
                          maxLines: 6,
                        ),
                      ],
                    ),
                  ),
                  if (!widget.noteOnly) ...[
                    const SizedBox(height: 14),
                    AppPickerField(
                      onPressed: !editable
                          ? null
                          : () async {
                              final result = await VersionPicker.show(
                                context: context,
                                selected: widget.draft.version,
                              );
                              if (mounted && editable && result != null) {
                                setState(
                                  () => widget.draft.version = result.value,
                                );
                              }
                            },
                      label: '버전',
                      value: formatVersionCode(widget.draft.version),
                    ),
                    AppPickerField(
                      onPressed: !editable
                          ? null
                          : () async {
                              final result = await MusicalKeyPicker.song(
                                context: context,
                                selected: widget.draft.musicalKey,
                              );
                              if (mounted && editable && result != null) {
                                setState(
                                  () => widget.draft.musicalKey = result.value,
                                );
                              }
                            },
                      label: '대표 키',
                      value: widget.draft.musicalKey == null
                          ? '미정'
                          : formatMusicalKey(widget.draft.musicalKey!),
                    ),
                    AppPickerField(
                      onPressed: !editable
                          ? null
                          : () async {
                              final result = await TierPicker.song(
                                context: context,
                                selected: widget.draft.tier,
                              );
                              if (mounted && editable && result != null) {
                                setState(
                                  () => widget.draft.tier = result.value,
                                );
                              }
                            },
                      label: '곡 티어',
                      value: formatSongTier(widget.draft.tier),
                    ),
                    SongSuitabilityChoice(
                      value: widget.draft.isSuitable,
                      onChanged: !editable
                          ? null
                          : (v) => setState(() => widget.draft.isSuitable = v),
                    ),
                  ],
                  if (error != null) Text(error!, semanticsLabel: error),
                  FilledButton(
                    onPressed: busy || revoked ? null : save,
                    child: Text(
                      busy
                          ? '저장 중'
                          : command == null
                          ? '저장'
                          : '같은 변경 다시 저장',
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
      ),
    ),
  );
}
