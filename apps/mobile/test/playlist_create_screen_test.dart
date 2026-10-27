import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/playlists/playlist_create_screen.dart';
import 'package:song_record/features/playlists/playlist_library_screen.dart';

void main() {
  for (final light in [false, true]) {
    testWidgets(
      'create page preserves name, default icon and neutral theme $light',
      (tester) async {
        ({String name, String icon})? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.preview(light: light),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.push(
                      context,
                      MaterialPageRoute<({String name, String icon})>(
                        builder: (_) => const PlaylistCreateScreen(
                          icons: playlistIcons,
                          labels: playlistIconLabels,
                        ),
                      ),
                    );
                  },
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        expect(find.text('새 플레이리스트'), findsOneWidget);
        expect(find.text('선택하지 않으면 음표로 만들어요'), findsOneWidget);
        expect(find.text('만들기'), findsOneWidget);
        final theme = Theme.of(tester.element(find.byType(TextField)));
        expect(theme.dialogTheme.backgroundColor, theme.colorScheme.surface);
        expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
        await tester.enterText(find.byType(TextField), '시험 목록');
        await tester.tap(find.text('만들기'));
        await tester.pumpAndSettle();
        expect(result, (name: '시험 목록', icon: 'music'));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
