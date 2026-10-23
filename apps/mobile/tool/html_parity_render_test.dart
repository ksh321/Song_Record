// Local visual comparison using actual product widgets and synthetic data only.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/app/app_shell.dart';
import 'package:song_record/app/app_tab.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_appearance.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/features/charts/popular_chart.dart';
import 'package:song_record/features/charts/popular_chart_screen.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:song_record/features/playlists/playlist_library_screen.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recording_classification_picker.dart';
import 'package:song_record/features/recorder/recording_list.dart';
import 'package:song_record/features/recorder/recording_workspace.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';
import 'package:song_record/features/settings/classification_screen.dart';
import 'package:song_record/features/settings/settings_screen.dart';
import 'package:song_record/features/settings/storage_screen.dart';
import 'package:song_record/features/songs/my_song.dart';
import 'package:song_record/features/songs/my_song_detail.dart';
import 'package:song_record/features/songs/my_songs_screen.dart';
import 'package:song_record/features/songs/song_detail_screen.dart';
import 'package:song_record/features/songs/song_edit.dart';
import 'package:song_record/features/songs/song_edit_screen.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
const titles = ['밤 산책', '푸른 계절', '너의 계절', '오래된 편지', '우리의 밤', '새벽의 메모'];
const artists = ['윤서', '하린', '이든', '서우', '민재', '직접 입력 가수'];
Map<String, dynamic> song(int i) => {
  'id': id(i + 1),
  'title': titles[i],
  'artist': artists[i],
  'version_code': 'NORMAL',
  'tier': i == 5 ? null : ['S', 'A', 'B', 'C', 'D'][i],
  'note': '',
  'lifecycle_state': 'ACTIVE',
  'is_suitable': i == 0 || i == 3,
  'created_at': '2026-10-${20 - i}T00:00:00Z',
  'tj_number': i == 5 ? null : ['04567', '07890', '04568', '04569', '04570'][i],
  'representative_key_mode': i == 1 ? 'FEMALE' : 'ORIGINAL',
  'representative_key_shift': i == 1 ? 1 : 0,
};
Map<String, dynamic> recording(int i) => {
  'id': id(20 + i),
  'song_id': id(1),
  'title_snapshot': titles[i % 2],
  'artist_snapshot': artists[i % 2],
  'version_code': 'NORMAL',
  'key_mode': 'ORIGINAL',
  'key_shift': 0,
  'tier': i == 1 ? 'B' : null,
  'note': '',
  'metadata_state': 'SAVED',
  'lifecycle_state': 'ACTIVE',
  'timezone_id': 'Asia/Seoul',
  'timezone_offset_minutes': 540,
  'recorded_at': '2026-09-${15 - i}T11:48:00Z',
  'file': {'duration_ms': i == 0 ? 12000 : 222000},
};
final detail = MySongDetail({
  'song': song(0),
  'revision': 1,
  'recordings': [recording(0), recording(1)],
});

class DemoRecorder implements RecorderGateway {
  const DemoRecorder();
  @override
  Stream<RecorderStatus> watchStatus() => const Stream.empty();
  @override
  Future<RecorderStatus> getCurrentStatus() async =>
      const RecorderStatus.idle();
  @override
  Future<RecorderDeviceInfo> getDeviceInfo() async => const RecorderDeviceInfo(
    manufacturer: 'synthetic',
    model: 'visual',
    androidVersion: 'test',
    sdkInt: 36,
  );
  @override
  Future<RecorderPermissions> requestPermissions() async =>
      const RecorderPermissions(
        microphoneGranted: true,
        notificationsGranted: true,
      );
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> playLatest() async {}
  @override
  Future<void> openAppSettings() async {}
}

void main() {
  testWidgets('render actual app screens against HTML at 380 logical pixels', (
    tester,
  ) async {
    final loader = FontLoader('ReferenceKR')
      ..addFont(rootBundle.load('assets/fonts/ReferenceKR.ttf'));
    final fallback = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/ReferenceKR.ttf'));
    await tester.runAsync(fallback.load);
    await tester.runAsync(loader.load);
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(iconLoader.load);
    tester.view.physicalSize = const Size(380, 708);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final output = Directory('../../.local/workflow/html-parity-render')
      ..createSync(recursive: true);
    late Directory temp;
    late AccountStoreManager stores;
    late PlaylistLibrary playlists;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('ui-parity-render-');
      stores = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => temp,
        temporaryDirectory: () async => temp,
      );
      playlists = PlaylistLibrary(
        LocalRepository(await stores.openAccount(id(900))),
      );
      await playlists.create('오늘 부를 곡')();
      await playlists.create('고음 연습')();
    });
    addTearDown(
      () => tester.runAsync(() async {
        await stores.logout();
        await temp.delete(recursive: true);
      }),
    );
    for (final light in [true, false]) {
      final appearance = ValueNotifier(light);
      for (final screen in [
        'songs',
        'search',
        'charts',
        'detail',
        'record',
        'recordings',
        'settings',
        'playlists',
        'storage',
        'edit',
        'classification',
        'personal',
        'accent',
        'conditions',
        'tags',
        'rename',
      ]) {
        final boundary = GlobalKey();
        final palette = ValueNotifier(AppAccent.purple);
        Widget personalization(BuildContext context) => ClassificationScreen(
          load: () async => (
            tags: [
              for (var i = 0; i < 3; i++)
                {
                  'id': id(100 + i),
                  'name': ['고음', '호흡', '발음'][i],
                  'revision': 1,
                  'archived_at': null,
                },
            ],
            conditions: [
              for (var i = 0; i < 3; i++)
                {
                  'id': id(200 + i),
                  'code': ['GOOD', 'NORMAL', 'BAD'][i],
                  'name': ['좋음', '보통', '피곤함'][i],
                  'revision': 1,
                  'archived_at': null,
                },
            ],
          ),
          command: (_, _, _, _) async {},
          requireCurrent: () {},
          accent: palette,
          saveAccent: (a) async => palette.value = a,
        );
        final home = switch (screen) {
          'personal' ||
          'accent' ||
          'conditions' ||
          'tags' ||
          'rename' => AppShell(
            recorderGateway: const DemoRecorder(),
            settingsBuilder: personalization,
            tabBuilder: (_, _) => const SizedBox(),
          ),
          'detail' => SongDetailScreen(watch: () => Stream.value(detail)),
          'recordings' => Scaffold(
            appBar: AppBar(title: const Text('전체 녹음')),
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RecordingList(
                rows: [recording(0), recording(1), recording(2)],
                scope: 'synthetic',
                onOpen: (_) {},
              ),
            ),
          ),
          'settings' => SettingsScreen(
            showDevelopmentTools: false,
            storageBuilder: (_) => const SizedBox(),
            backupBuilder: (_) => const SizedBox(),
            importBuilder: (_) => const SizedBox(),
            classificationBuilder: (_) => const SizedBox(),
            trashBuilder: (_) => const SizedBox(),
          ),
          'playlists' => Scaffold(
            appBar: AppBar(title: const Text('플레이리스트')),
            body: PlaylistLibraryScreen(library: playlists, embedded: true),
          ),
          'storage' => StorageScreen(
            load: () async => StorageView(
              {
                for (final k in StorageView.labels.keys) k: 0,
                'used_bytes': 184000000,
                'quota_bytes': 1000000000,
                'pinned_used': 3,
                'pinned_limit': 10,
                'entitlement_revision': 1,
              },
              [],
              [],
            ),
            requireCurrent: () {},
            command: (a, b, c, d) async {},
          ),
          'edit' => SongEditScreen(
            draft: SongEditDraft(detail),
            prepare: (_) => () async {},
          ),
          'classification' => RecordingClassificationPicker(
            options: (
              conditions: [
                {'code': 'GOOD', 'name': '좋음'},
              ],
              tags: [
                {'id': 'a', 'name': '고음'},
                {'id': 'b', 'name': '호흡'},
              ],
            ),
            selection: (condition: null, tags: []),
            isCurrent: () => true,
            manage: () async => (
              conditions: <Map<String, dynamic>>[],
              tags: <Map<String, dynamic>>[],
            ),
          ),
          _ => AppShell(
            recorderGateway: const DemoRecorder(),
            tabBuilder: (context, tab) => switch (tab) {
              AppTab.songs => MySongsScreen(
                watch: () =>
                    Stream.value([for (var i = 0; i < 6; i++) MySong(song(i))]),
                onFindSong: () {},
              ),
              AppTab.search => KaraokeSearchScreen(
                initialQuery: const KaraokeQuery(
                  KaraokeBrand.tj,
                  KaraokeKind.title,
                  '밤',
                ),
                load: (q) async => [
                  for (var i = 0; i < 5; i++)
                    KaraokeCandidate(
                      brand: q.brand,
                      number: '0456$i',
                      title: titles[i],
                      artist: artists[i],
                      provider: 'SYNTHETIC',
                      sourceRef: 'visual',
                      sourceToken: 'synthetic-proof',
                      expiresAt: null,
                    ),
                ],
              ),
              AppTab.charts => PopularChartScreen(
                load: (scope) async => PublishedChart(
                  scope: scope,
                  fetchedAt: DateTime.utc(2026, 10, 23),
                  revision: 1,
                  stale: false,
                  items: [
                    for (var i = 0; i < 5; i++)
                      ChartItem(
                        position: i + 1,
                        number: '0456$i',
                        title: titles[i],
                        artist: artists[i],
                      ),
                  ],
                ),
              ),
              AppTab.recording => RecordingWorkspace(
                gateway: const DemoRecorder(),
                repository: () => null,
                isCurrent: (_) => true,
              ),
              _ => const SizedBox(),
            },
          ),
        };
        Future<void> mount() async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: AppAppearance(
                light: appearance,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.preview(
                    light: light,
                    accent: AppAccent.purple,
                  ),
                  home: home,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (screen == 'playlists') {
            final deadline = DateTime.now().add(const Duration(seconds: 5));
            while (DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await tester.pump();
              if (find.text('오늘 부를 곡').evaluate().isNotEmpty) break;
            }
            await tester.pumpAndSettle();
            expect(find.text('오늘 부를 곡'), findsOneWidget);
          }
        }

        if (screen == 'playlists') {
          await tester.runAsync(mount);
        } else {
          await mount();
        }
        if ([
          'personal',
          'accent',
          'conditions',
          'tags',
          'rename',
        ].contains(screen)) {
          await tester.tap(find.byTooltip('설정'));
          await tester.pumpAndSettle();
          if (screen != 'personal') {
            await tester.tap(
              find.text(switch (screen) {
                'accent' => '강조색',
                'conditions' => '컨디션 관리',
                _ => '태그 관리',
              }),
            );
            await tester.pumpAndSettle();
          }
          if (screen == 'rename') {
            await tester.tap(find.byTooltip('이름 변경').first);
            await tester.pumpAndSettle();
          }
        }
        if (['search', 'charts', 'record'].contains(screen)) {
          final label = {
            'search': '검색',
            'charts': '인기 차트',
            'record': '녹음',
          }[screen]!;
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(label),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull, reason: '$screen/$light');
        await tester.runAsync(() async {
          final img =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/$screen-${light ? 'light' : 'dark'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        palette.dispose();
      }
      appearance.dispose();
    }
  });
}
