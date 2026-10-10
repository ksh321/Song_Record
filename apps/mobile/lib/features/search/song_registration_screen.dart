import 'package:flutter/material.dart';

import '../../core/domain/input_validation.dart';
import '../../core/domain/song_types.dart';
import '../../core/widgets/version_picker.dart';
import 'karaoke_search.dart';
import 'search_intent.dart';
import 'song_registration.dart';

class SongRegistrationScreen extends StatefulWidget {
  const SongRegistrationScreen({
    required this.prepare,
    required this.intent,
    this.candidate,
    this.manualApproval,
    super.key,
  });
  final SongRegistrationPreparer prepare;
  final SearchIntent intent;
  final KaraokeCandidate? candidate;
  final ManualSearchApproval? manualApproval;
  @override
  State<SongRegistrationScreen> createState() => _SongRegistrationScreenState();
}

class _SongRegistrationScreenState extends State<SongRegistrationScreen> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, artist;
  final note = TextEditingController();
  VersionCode version = VersionCode.normal;
  Future<void> Function()? _savePrepared;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.intent.validate();
    if ((widget.candidate == null) == (widget.manualApproval == null) ||
        widget.candidate != null &&
            widget.candidate!.brand != KaraokeBrand.tj) {
      throw ArgumentError('Verified TJ or approved manual input is required');
    }
    final c = widget.candidate, q = widget.manualApproval?.query;
    title = TextEditingController(
      text: c?.title ?? (q?.kind == KaraokeKind.title ? q!.text : ''),
    );
    artist = TextEditingController(
      text: c?.artist ?? (q?.kind == KaraokeKind.artist ? q!.text : ''),
    );
  }

  @override
  void dispose() {
    title.dispose();
    artist.dispose();
    note.dispose();
    super.dispose();
  }

  String? validate(InputField field, String? value) =>
      validateInput(field, value ?? '').isValid ? null : '입력 길이를 확인해 주세요.';
  Future<void> _save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      _savePrepared ??= widget.prepare(
        SongRegistrationDraft(
          intent: widget.intent,
          candidate: widget.candidate,
          manualApproval: widget.manualApproval,
          title: title.text,
          artist: artist.text,
          note: note.text,
          version: version,
        ),
      );
      await _savePrepared!();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => error = '저장하지 못했어요. 입력을 유지했습니다. 같은 내용으로 다시 저장해 주세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.candidate == null ? '직접 등록' : '내 곡 등록'),
      ),
      body: SafeArea(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.candidate != null)
                Text('TJ ${widget.candidate!.number} · 원본 정보와 편집값을 따로 보관해요.'),
              if (widget.candidate == null)
                const Text('정상 TJ 검색에서 찾지 못한 곡을 직접 등록해요. 번호는 입력하지 않습니다.'),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('song-title'),
                controller: title,
                readOnly: busy || _savePrepared != null,
                decoration: const InputDecoration(labelText: '곡명'),
                validator: (v) => validate(InputField.title, v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('song-artist'),
                controller: artist,
                readOnly: busy || _savePrepared != null,
                decoration: const InputDecoration(labelText: '가수'),
                validator: (v) => validate(InputField.artist, v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('song-note'),
                controller: note,
                readOnly: busy || _savePrepared != null,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '메모'),
                validator: (v) => validate(InputField.note, v),
              ),
              TextButton(
                onPressed: busy || _savePrepared != null
                    ? null
                    : () async {
                        final choice = await VersionPicker.show(
                          context: context,
                          selected: version,
                        );
                        if (mounted && choice != null) {
                          setState(() => version = choice.value);
                        }
                      },
                child: Text('버전: ${formatVersionCode(version)}'),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : _save,
                child: Text(busy ? '저장 중' : '이 기기에 저장'),
              ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
