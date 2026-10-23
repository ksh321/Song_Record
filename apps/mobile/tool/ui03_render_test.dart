// Local visual audit: synthetic values, no account/DB/network operations.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/feature_icon.dart';
import 'package:song_record/core/widgets/music_view_data.dart';
import 'package:song_record/core/widgets/song_row.dart';

void main() {
  testWidgets('render shared beta surfaces in both appearances', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final family in ['Roboto', ...AppTypography.familyStack]) {
        final loader = FontLoader(family);
        loader.addFont(
          File('C:/Windows/Fonts/malgun.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
        await loader.load();
      }
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final boundary = GlobalKey();
    final output = Directory('../../.local/workflow/beta-ui-render')
      ..createSync(recursive: true);
    for (final light in [false, true]) {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.preview(light: light, accent: AppAccent.purple),
            home: Scaffold(
              appBar: AppBar(title: const Text('내 곡')),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Wrap(
                    spacing: 12,
                    children: [
                      FeatureIcon(Icons.music_note_outlined),
                      FeatureIcon(Icons.queue_music),
                      FeatureIcon(Icons.search),
                      FeatureIcon(Icons.edit_outlined),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const TextField(
                    decoration: InputDecoration(hintText: '내 곡에서 곡명 또는 가수 검색'),
                  ),
                  for (var i = 0; i < 6; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SongRow.registered(
                        song: RegisteredSongViewData(
                          id: SongId(
                            '00000000-0000-4000-8000-00000000000${i + 1}',
                          ),
                          title: [
                            '밤 산책',
                            '푸른 계절',
                            '너의 계절',
                            '오래된 편지',
                            '우리의 밤',
                            '새벽의 메모',
                          ][i],
                          artist: '샘플 가수',
                          version: VersionCode.normal,
                          tier: i == 5 ? null : SongTier.values[i],
                          musicalKey: i.isEven
                              ? MusicalKey.original
                              : MusicalKey(mode: KeyMode.female, shift: 1),
                          isSuitable: i == 0 || i == 3,
                        ),
                        onTap: () {},
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File('${output.path}/${light ? 'light' : 'dark'}.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
