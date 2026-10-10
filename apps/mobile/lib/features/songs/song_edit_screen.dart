import 'package:flutter/material.dart';

import '../../core/domain/song_types.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/musical_key_picker.dart';
import '../../core/widgets/tier_picker.dart';
import '../../core/widgets/version_picker.dart';
import '../auth/auth_session.dart';
import 'song_edit.dart';

class SongEditScreen extends StatefulWidget {
  const SongEditScreen({
    required this.draft,
    required this.prepare,
    this.auth,
    super.key,
  });
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
              ? '곡명·가수는 1~200자, 아쉬운 점은 2,000자 이내로 입력해 주세요.'
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
      appBar: AppBar(title: const Text('곡 수정')),
      body: SafeArea(
        child: revoked
            ? const ContentState(
                phase: ContentPhase.waiting,
                title: '계정이 변경됐어요. 편집을 닫고 다시 열어 주세요.',
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  TextField(
                    controller: title,
                    enabled: editable,
                    decoration: const InputDecoration(labelText: '곡명'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: artist,
                    enabled: editable,
                    decoration: const InputDecoration(labelText: '가수'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: note,
                    enabled: editable,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '아쉬운 점 (최대 2,000자)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
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
                    child: Text(
                      '버전: ${formatVersionCode(widget.draft.version)}',
                    ),
                  ),
                  OutlinedButton(
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
                    child: Text(
                      '대표 키: ${widget.draft.musicalKey == null ? '미정' : formatMusicalKey(widget.draft.musicalKey!)}',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: !editable
                        ? null
                        : () async {
                            final result = await TierPicker.song(
                              context: context,
                              selected: widget.draft.tier,
                            );
                            if (mounted && editable && result != null) {
                              setState(() => widget.draft.tier = result.value);
                            }
                          },
                    child: Text('곡 티어: ${formatSongTier(widget.draft.tier)}'),
                  ),
                  if (error != null) Text(error!, semanticsLabel: error),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: busy ? null : save,
                    child: Text(
                      busy
                          ? '저장 중'
                          : command == null
                          ? '저장'
                          : '같은 변경 다시 저장',
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                  ),
                ],
              ),
      ),
    ),
  );
}
