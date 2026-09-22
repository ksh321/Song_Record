import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';

/// Run with: flutter run --debug --flavor dev -t tool/preview_theme.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'dev') {
    throw StateError('Theme preview requires the debug dev flavor.');
  }
  runApp(const ThemePreviewApp());
}

class ThemePreviewApp extends StatefulWidget {
  const ThemePreviewApp({super.key});

  @override
  State<ThemePreviewApp> createState() => _ThemePreviewAppState();
}

class _ThemePreviewAppState extends State<ThemePreviewApp> {
  AppAccent _accent = AppAccent.initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '테마 미리보기',
    theme: AppTheme.dark(accent: _accent),
    // Instant switching also makes reduced-motion inspection deterministic.
    themeAnimationDuration: Duration.zero,
    home: Scaffold(
      appBar: AppBar(title: const Text('테마 미리보기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text('P05-01 · 색상과 치수 확인'),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '버튼은 모양 확인용이에요. 녹음이나 저장은 실행하지 않아요.',
              style: AppTypography.supporting,
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final accent in AppAccent.values)
                  OutlinedButton.icon(
                    key: ValueKey('accent-${accent.id}'),
                    onPressed: () => setState(() => _accent = accent),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent.foreground,
                      backgroundColor: accent.background,
                    ),
                    icon: Icon(
                      accent == _accent
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                    ),
                    label: Text(accent.label),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('선택한 강조색: ${_accent.label}'),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '곡 상세 제목 · 20',
                      style: AppTypography.detailTitle,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      '긴 곡명과 가수명이 여러 줄로 표시되어도 내용을 확인할 수 있어요',
                      style: AppTypography.songTitle,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('본문 · 14'),
                    const Text('보조 글자 · 12', style: AppTypography.supporting),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(onPressed: () {}, child: const Text('주요 버튼')),
                    const SizedBox(height: AppSpacing.sm),
                    const FilledButton(
                      onPressed: null,
                      child: Text('사용할 수 없는 버튼'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('보조 버튼'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const TextField(
                      decoration: InputDecoration(
                        labelText: '곡명',
                        hintText: '글자 크기와 키보드를 확인해 보세요',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: const [
                        _KeySample('원키', AppColors.keyOriginalBackground),
                        _KeySample('남 0', AppColors.keyMaleBackground),
                        _KeySample('여 +1', AppColors.keyFemaleBackground),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () {},
                      style: AppTheme.recordingFilledButtonStyle,
                      icon: const Icon(Icons.mic),
                      label: const Text('녹음 시작 모양'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () {},
                      style: AppTheme.recordingOutlinedButtonStyle,
                      icon: const Icon(Icons.stop),
                      label: const Text('녹음 종료 모양'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _KeySample extends StatelessWidget {
  const _KeySample(this.label, this.background);

  final String label;
  final Color background;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppDimensions.viewToggleRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.keyForeground,
          fontSize: AppTypography.keyBadgeSize,
        ),
      ),
    ),
  );
}
