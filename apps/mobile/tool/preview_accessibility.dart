import 'package:flutter/material.dart';
import 'package:song_record/app/app_tab.dart';
import 'package:song_record/core/domain/domain_ordering.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/musical_key_picker.dart';
import 'package:song_record/core/widgets/recording_roles_card.dart';
import 'package:song_record/core/widgets/selection_sheet.dart';
import 'package:song_record/core/widgets/song_discovery_sheet.dart';
import 'package:song_record/core/widgets/song_row.dart';
import 'package:song_record/core/widgets/song_summary.dart';
import 'package:song_record/routing/tab_navigation.dart';

// This entrypoint and its controls are not imported by the production app.
void main() => runApp(const AccessibilityPreviewApp());

class _PreviewOptions extends ChangeNotifier {
  double? scale;
  bool? reduced;

  void setScale(double? value) {
    scale = value;
    notifyListeners();
  }

  void setReduced(bool? value) {
    reduced = value;
    notifyListeners();
  }
}

class AccessibilityPreviewApp extends StatefulWidget {
  const AccessibilityPreviewApp({super.key});

  @override
  State<AccessibilityPreviewApp> createState() =>
      _AccessibilityPreviewAppState();
}

class _AccessibilityPreviewAppState extends State<AccessibilityPreviewApp> {
  final _options = _PreviewOptions();

  @override
  void dispose() {
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _options,
    builder: (context, _) => MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: _options.scale == null
                ? media.textScaler
                : TextScaler.linear(_options.scale!),
            disableAnimations: _options.reduced ?? media.disableAnimations,
            accessibleNavigation:
                _options.reduced ?? media.accessibleNavigation,
          ),
          child: child!,
        );
      },
      home: Builder(
        builder: (context) => TabNavigator(
          tab: AppTab.songs,
          active: true,
          openSettings: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => _TestControls(options: _options),
            ),
          ),
          rootBuilder: (_) => const SafeArea(top: false, child: _Preview()),
        ),
      ),
    ),
  );
}

class _TestControls extends StatelessWidget {
  const _TestControls({required this.options});

  final _PreviewOptions options;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: options,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('테스트 설정')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('이 미리보기에서만 적용돼요. 앱을 종료하면 초기화돼요.'),
            const SizedBox(height: 16),
            const Text('글자 크기'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in <double?>[null, 1, 1.3, 1.6, 2])
                  ChoiceChip(
                    label: Text(
                      value == null ? '시스템 글꼴' : '${value.toStringAsFixed(1)}배',
                    ),
                    selected: options.scale == value,
                    onSelected: (_) => options.setScale(value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('애니메이션'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in <bool?>[null, false, true])
                  ChoiceChip(
                    label: Text(
                      value == null
                          ? '시스템 모션'
                          : value
                          ? '모션 줄이기'
                          : '일반 모션',
                    ),
                    selected: options.reduced == value,
                    onSelected: (_) => options.setReduced(value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                options.setScale(null);
                options.setReduced(null);
              },
              child: const Text('시스템 설정으로 초기화'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('샘플로 돌아가기'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Preview extends StatefulWidget {
  const _Preview();

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  MusicalKey? _key;
  final _id = SongId('00000000-0000-4000-8000-000000000001');

  @override
  Widget build(BuildContext context) {
    final song = RegisteredSongViewData(
      id: _id,
      title: '작은 화면에서도 끝까지 읽을 수 있어야 하는 아주 긴 노래 제목',
      artist: '길이가 긴 가수 이름',
      version: VersionCode.normal,
      musicalKey: _key,
      note: '이 화면은 저장하지 않는 메모리 샘플이에요.',
    );
    void detail() => TabNavigation.of(context).openPage<void>(
      title: song.title,
      builder: (_) => SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(song.title),
            const Text('뒤로가면 입력한 문구와 스크롤 위치로 돌아가요.'),
          ],
        ),
      ),
    );
    return ListView(
      key: const PageStorageKey('accessibility-preview'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('화면 확인용 샘플 · 오른쪽 위 톱니바퀴에서 글자 크기와 애니메이션을 바꿔 보세요.'),
        const SizedBox(height: 16),
        const TextField(decoration: InputDecoration(labelText: '키보드 확인용 입력')),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => showSongDiscoverySheet(
            context: context,
            playlistId: 'preview',
            playlistTitle: '연습 목록',
          ),
          child: const Text('새 곡 찾기'),
        ),
        OutlinedButton(
          onPressed: () => showSelectionSheet<int>(
            context: context,
            title: '버전 선택',
            selected: 0,
            options: const [
              SelectionOption(0, '일반 반주'),
              SelectionOption(1, 'MR'),
              SelectionOption(2, 'LIVE'),
            ],
          ),
          child: const Text('버전 선택'),
        ),
        OutlinedButton(
          onPressed: () async {
            final result = await MusicalKeyPicker.song(
              context: context,
              selected: _key,
            );
            if (!mounted || result == null) {
              return;
            }
            setState(() => _key = result.value);
          },
          child: const Text('키 선택'),
        ),
        SongRow.registered(song: song, onTap: detail),
        SongSummary(song: song, onEdit: detail),
        RecordingRolesCard(
          songId: _id,
          selection: const RecordingSelection(),
          recordings: const {},
        ),
      ],
    );
  }
}
