import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/app/app_shell.dart';
import 'package:song_record/app/song_record_app.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/charts/popular_chart_screen.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';

import 'auth_session_test.dart' as fixtures;

const owner = '00000000-0000-4000-8000-000000000001';
const other = '00000000-0000-4000-8000-000000000002';

void main() {
  test('same active store survives new facades, while a replaced lease is rejected', () async {
    final directory = await Directory.systemTemp.createTemp('candidate-lease-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => directory,
      temporaryDirectory: () async => directory,
    );
    try {
      final store = await manager.openAccount(owner);
      final first = LocalRepository(store), second = LocalRepository(store);
      expect(identical(first, second), isFalse);
      expect(first.sharesActiveStoreWith(second), isTrue);
      final replaced = LocalRepository(await manager.openAccount(owner));
      expect(() => first.sharesActiveStoreWith(replaced), throwsStateError);
    } finally {
      await manager.logout();
      await directory.delete(recursive: true);
    }
  });
  testWidgets(
    'production candidate callbacks accept fresh wrappers and reject switched accounts',
    (t) async {
      late Directory directory;
      late AccountStoreManager manager;
      late AccountStore store;
      await t.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'candidate-production-',
        );
        manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => directory,
          temporaryDirectory: () async => directory,
        );
        store = await manager.openAccount(owner);
      });
      final auth = AuthController(
        api: fixtures.Api(),
        vault: fixtures.Vault(),
        proofs: fixtures.Proofs(),
        openAccount: (_) async {},
        closeAccount: () async {},
        now: () => fixtures.time,
      );
      auth.session = fixtures.session(user: owner);
      auth.phase = AuthPhase.ready;
      auth.notifyListeners();
      var wrappers = 0;
      try {
        await t.runAsync(() async {
          await t.pumpWidget(
            SongRecordApp(
              config: AppConfig(
                environment: AppEnvironment.dev,
                apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
              ),
              authController: auth,
              accountStore: () => store,
              // This is the production main.dart getter contract, not a stable facade.
              localRepository: () {
                wrappers++;
                return LocalRepository(store);
              },
            ),
          );
          await t.pump();
        });
        final shell = t.widget<AppShell>(find.byType(AppShell));
        final context = t.element(find.byType(AppShell));
        final chart = shell.chartBuilder!(context) as PopularChartScreen;
        final search = shell.searchBuilder!(context) as KaraokeSearchScreen;
        expect(chart.candidateActions, same(search.candidateActions));
        final actions = chart.candidateActions!;
        final membership = await t.runAsync(
          () =>
              actions.membership('00123').timeout(const Duration(seconds: 10)),
        );
        expect(membership!.songId, isNull);
        expect(membership.playlistCount, 0);
        expect(wrappers, greaterThan(1));
        await t.runAsync(() async {
          final pending = actions.membership('00123');
          auth.session = fixtures.session(user: other);
          auth.notifyListeners();
          await expectLater(pending, throwsStateError);
          expect(await LocalRepository(store).pending(), isEmpty);
        });
      } finally {
        await t.runAsync(() => t.pumpWidget(const SizedBox.shrink()));
        auth.dispose();
        await t.runAsync(() async {
          await manager.logout();
          await directory.delete(recursive: true);
        });
      }
    },
  );
}
