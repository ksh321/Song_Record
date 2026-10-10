import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';
import 'package:song_record/features/search/search_intent.dart';
import 'package:song_record/features/search/song_registration.dart';
import 'package:song_record/features/search/song_registration_screen.dart';

import 'karaoke_search_test.dart' show row;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'only successful current TJ search offers manual, never waiting, error or KY',
    (tester) async {
      final response = Completer<List<KaraokeCandidate>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaraokeSearchScreen(
              load: (_) => response.future,
              prepareRegistration: (_) => () async {},
            ),
          ),
        ),
      );
      expect(find.text('찾는 곡이 없어요'), findsNothing);
      await tester.enterText(find.byType(TextField), '곡');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('찾는 곡이 없어요'), findsNothing);
      response.complete([]);
      await tester.pump();
      expect(find.text('찾는 곡이 없어요'), findsOneWidget);
      await tester.tap(find.text('금영'));
      await tester.pump();
      expect(find.text('찾는 곡이 없어요'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaraokeSearchScreen(
              key: const ValueKey('error-screen'),
              initialQuery: const KaraokeQuery(
                KaraokeBrand.tj,
                KaraokeKind.title,
                '곡',
              ),
              load: (_) async => throw const KaraokeFailure('외부 장애'),
              prepareRegistration: (_) => () async {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('찾는 곡이 없어요'), findsNothing);
      expect(find.text('외부 장애'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'manual requires human confirmation and cancellation creates no command',
    (tester) async {
      var prepared = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KaraokeSearchScreen(
              initialQuery: const KaraokeQuery(
                KaraokeBrand.tj,
                KaraokeKind.title,
                '찾는 곡',
              ),
              load: (_) async => [],
              prepareRegistration: (_) {
                prepared++;
                return () async {};
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.text('찾는 곡이 없어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.byType(SongRegistrationScreen), findsNothing);
      expect(prepared, 0);
      await tester.tap(find.text('찾는 곡이 없어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('찾는 곡 없음 확인'));
      await tester.pumpAndSettle();
      expect(find.byType(SongRegistrationScreen), findsOneWidget);
      expect(prepared, 0);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('song-title')))
            .controller!
            .text,
        '찾는 곡',
      );
      expect(find.text('TJ 번호'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'offline input and failed save persist, retry prepares once and saves the same command',
    (tester) async {
      final c = KaraokeSearchController((_) async => []);
      c.change(text: '직접 곡');
      await tester.pump(const Duration(milliseconds: 400));
      final approval = c.approveManual();
      c.dispose();
      var prepared = 0, attempts = 0;
      SongRegistrationDraft? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<bool>(
                    builder: (_) => SongRegistrationScreen(
                      intent: const SearchIntent(),
                      manualApproval: approval,
                      prepare: (d) {
                        prepared++;
                        submitted = d;
                        return () async {
                          attempts++;
                          if (attempts == 1) {
                            throw StateError('local save unavailable');
                          }
                        };
                      },
                    ),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('song-artist')),
        '직접 가수',
      );
      await tester.enterText(
        find.byKey(const ValueKey('song-note')),
        '오프라인 메모',
      );
      await tester.ensureVisible(find.text('이 기기에 저장'));
      await tester.tap(find.text('이 기기에 저장'));
      await tester.pumpAndSettle();
      expect(prepared, 1);
      expect(attempts, 1);
      expect(find.textContaining('입력을 유지했습니다'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('song-note')))
            .controller!
            .text,
        '오프라인 메모',
      );
      expect(submitted!.manualApproval, same(approval));
      await tester.ensureVisible(find.text('이 기기에 저장'));
      await tester.tap(find.text('이 기기에 저장'));
      await tester.pumpAndSettle();
      expect(prepared, 1);
      expect(attempts, 2);
      expect(find.byType(SongRegistrationScreen), findsNothing);
    },
  );
  test(
    'normal completed search is required for approval and KY draft is rejected',
    () async {
      final c = KaraokeSearchController((_) async => []);
      expect(c.approveManual, throwsStateError);
      c.change(brand: KaraokeBrand.ky, text: '곡');
      c.retry();
      await Future<void>.delayed(Duration.zero);
      expect(c.approveManual, throwsStateError);
      c.dispose();
      expect(
        () => SongRegistrationDraft(
          intent: const SearchIntent(),
          title: '곡',
          artist: '가수',
          candidate: row(KaraokeBrand.ky, '1'),
        ),
        throwsArgumentError,
      );
    },
  );
  test('manual and TJ input persist offline across reopening, replay keeps one immutable operation', () async {
    final root = await Directory.systemTemp.createTemp(
      'song-record-search-registration-',
    );
    var manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    const owner = '00000000-0000-4000-8000-000000000001';
    try {
      var repo = LocalRepository(await manager.openAccount(owner));
      final c = KaraokeSearchController((_) async => []);
      c.change(text: '직접 곡');
      c.retry();
      await Future<void>.delayed(Duration.zero);
      final approval = c.approveManual();
      c.dispose();
      final manual = SongRegistrationDraft(
        intent: const SearchIntent(),
        title: ' 직접 곡 ',
        artist: '가수',
        note: 'offline draft',
        manualApproval: approval,
      ).prepare(repo);
      final tj = SongRegistrationDraft(
        intent: const SearchIntent(),
        title: '원본 (LIVE)',
        artist: '가수',
        candidate: row(KaraokeBrand.tj, '00123'),
      ).prepare(repo);
      expect(
        jsonDecode(manual.changesJson),
        containsPair('manual_reason', 'TJ_NOT_FOUND'),
      );
      expect(jsonDecode(manual.changesJson), isNot(contains('source_token')));
      expect(jsonDecode(manual.changesJson), isNot(contains('tj_number')));
      expect(
        jsonDecode(tj.changesJson),
        containsPair('source_token', 's1.fixture'),
      );
      expect(jsonDecode(tj.changesJson), isNot(contains('tj_number')));
      expect(jsonDecode(tj.draftJson), containsPair('tj_number', '00123'));
      expect(
        jsonDecode(tj.changesJson),
        containsPair('version_code', 'NORMAL'),
      );
      await repo.save(manual);
      await repo.save(manual);
      await repo.save(tj);
      await manager.logout();
      manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => root,
        temporaryDirectory: () async => root,
      );
      repo = LocalRepository(await manager.openAccount(owner));
      final pending = await repo.pending();
      expect(pending, hasLength(2));
      expect(pending.where((x) => x.opId == manual.opId), hasLength(1));
      expect(
        jsonDecode(pending.singleWhere((x) => x.opId == manual.opId).payload),
        containsPair('note', 'offline draft'),
      );
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
