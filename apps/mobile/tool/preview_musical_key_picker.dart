import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/musical_key_picker.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: const MusicalKeyPreview(),
  ),
);

/// Local-memory samples make representative and saved recording keys visibly
/// independent. This preview does not write a song, a recording, or a database.
class MusicalKeyPreview extends StatefulWidget {
  const MusicalKeyPreview({super.key});

  @override
  State<MusicalKeyPreview> createState() => _MusicalKeyPreviewState();
}

class _MusicalKeyPreviewState extends State<MusicalKeyPreview> {
  MusicalKey? morningSongKey;
  MusicalKey? eveningSongKey = MusicalKey(mode: KeyMode.female, shift: 1);
  MusicalKey morningRecordingKey = MusicalKey.original;
  MusicalKey eveningRecordingKey = MusicalKey(mode: KeyMode.male, shift: -1);
  MusicalKey newRecordingKey = MusicalKey.original;
  String message = '곡의 대표 키와 이미 저장된 녹음 키를 각각 바꿔 보세요.';

  Future<void> editSong({required bool morning}) async {
    final result = await MusicalKeyPicker.song(
      context: context,
      selected: morning ? morningSongKey : eveningSongKey,
    );
    if (!mounted || result == null) return;
    setState(() {
      if (morning) {
        morningSongKey = result.value;
      } else {
        eveningSongKey = result.value;
      }
      message = '대표 키를 바꿨어요. 이미 저장된 녹음의 키는 그대로예요.';
    });
  }

  Future<void> editRecording({required bool morning}) async {
    final result = await MusicalKeyPicker.recording(
      context: context,
      selected: morning ? morningRecordingKey : eveningRecordingKey,
    );
    if (!mounted || result == null) return;
    setState(() {
      if (morning) {
        morningRecordingKey = result.value;
      } else {
        eveningRecordingKey = result.value;
      }
      message = '이 녹음의 키만 바꿨어요. 곡 대표 키는 그대로예요.';
    });
  }

  Future<void> editDraft() async {
    final result = await MusicalKeyPicker.recording(
      context: context,
      selected: newRecordingKey,
    );
    if (!mounted || result == null) return;
    setState(() {
      newRecordingKey = result.value;
      message = '새 녹음의 키만 바꿨어요.';
    });
  }

  void copySongDefault() {
    setState(() {
      newRecordingKey = morningSongKey ?? MusicalKey.original;
      message = '아침 노래의 현재 대표 키를 새 녹음에 채웠어요.';
    });
  }

  String label(MusicalKey? key) => key == null ? '미정' : formatMusicalKey(key);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('키 선택 미리보기')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('검증용 샘플 · 실제 곡이나 녹음은 바뀌지 않아요.'),
        const SizedBox(height: 16),
        Semantics(liveRegion: true, child: Text(message)),
        const SizedBox(height: 24),
        const Text('내 곡의 대표 키', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            key: const ValueKey('morning-song-key'),
            title: const Text('아침 노래'),
            subtitle: Text('대표 키 · ${label(morningSongKey)}'),
            trailing: const Icon(Icons.tune),
            onTap: () => editSong(morning: true),
          ),
        ),
        Card(
          child: ListTile(
            key: const ValueKey('evening-song-key'),
            title: const Text('저녁 노래'),
            subtitle: Text('대표 키 · ${label(eveningSongKey)}'),
            trailing: const Icon(Icons.tune),
            onTap: () => editSong(morning: false),
          ),
        ),
        const SizedBox(height: 24),
        const Text('이미 저장된 녹음의 키', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            key: const ValueKey('morning-recording-key'),
            title: const Text('아침 노래 · 지난 녹음'),
            subtitle: Text('녹음 키 · ${label(morningRecordingKey)}'),
            trailing: const Icon(Icons.tune),
            onTap: () => editRecording(morning: true),
          ),
        ),
        Card(
          child: ListTile(
            key: const ValueKey('evening-recording-key'),
            title: const Text('저녁 노래 · 지난 녹음'),
            subtitle: Text('녹음 키 · ${label(eveningRecordingKey)}'),
            trailing: const Icon(Icons.tune),
            onTap: () => editRecording(morning: false),
          ),
        ),
        const SizedBox(height: 24),
        const Text('아침 노래 · 새 녹음 준비', style: TextStyle(fontSize: 20)),
        OutlinedButton(
          key: const ValueKey('copy-song-default'),
          onPressed: copySongDefault,
          child: const Text('곡의 현재 대표 키 채우기'),
        ),
        Card(
          child: ListTile(
            key: const ValueKey('new-recording-key'),
            title: const Text('새 녹음 키 선택'),
            subtitle: Text('녹음 키 · ${label(newRecordingKey)}'),
            trailing: const Icon(Icons.tune),
            onTap: editDraft,
          ),
        ),
      ],
    ),
  );
}
