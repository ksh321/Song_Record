import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/search/karaoke_search.dart';
import 'package:song_record/features/search/karaoke_search_screen.dart';
import 'package:song_record/features/search/song_registration.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Use the isolated searchVerification debug flavor');
  }
  runApp(MaterialApp(theme: AppTheme.dark(), home: const SearchCheck()));
}

class SearchCheck extends StatefulWidget {
  const SearchCheck({super.key});
  @override
  State<SearchCheck> createState() => _CheckState();
}

class _CheckState extends State<SearchCheck> {
  AccountStoreManager? manager;
  LocalRepository? repository;
  String status = '별도 검사 저장소 준비 중';
  int saved = 0;
  bool failNext = false;
  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    try {
      final base = await getApplicationSupportDirectory();
      final root = Directory('${base.path}/p15-08-search');
      await root.create(recursive: true);
      manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => root,
        temporaryDirectory: () async => root,
      );
      // Each launch gets its own synthetic account. Previous tests are retained.
      final suffix = Random.secure()
          .nextInt(0x7fffffff)
          .toRadixString(16)
          .padLeft(12, '0');
      repository = LocalRepository(
        await manager!.openAccount('00001508-0000-4000-8000-$suffix'),
      );
      status = '준비 완료 · 개인 계정/서버 연결 없음';
    } catch (_) {
      status = '검사 저장소 준비 실패';
    }
    if (mounted) setState(() {});
  }

  KaraokeCandidate row(KaraokeBrand brand, String title, String number) =>
      KaraokeCandidate(
        brand: brand,
        number: number,
        title: title,
        artist: '검사 가수',
        provider: 'MANANA',
        sourceRef:
            'manana:${brand == KaraokeBrand.tj ? 'tj' : 'kumyoung'}:$number',
        sourceToken: 's1.fixture',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
      );

  Future<List<KaraokeCandidate>> load(int mode, KaraokeQuery q) async {
    if (mode == 4) {
      throw const KaraokeFailure('합성 외부 장애입니다. 빈 결과로 바꾸지 않습니다.');
    }
    if (mode == 3) return [];
    if (mode == 5) {
      await Future<void>.delayed(
        Duration(milliseconds: q.text == '이전' ? 2500 : 100),
      );
      return [row(q.brand, '${q.text} 결과', '00123')];
    }
    return [row(q.brand, '검사 원본 (LIVE)', '00123')];
  }

  Future<void> Function() save(SongRegistrationDraft draft) {
    final command = draft.prepare(repository!);
    return () async {
      if (failNext) {
        failNext = false;
        throw StateError('Controlled local save failure');
      }
      await repository!.save(command);
    };
  }

  Future<void> open(int mode) async {
    failNext = mode == 6;
    final brand = mode == 2 ? KaraokeBrand.ky : KaraokeBrand.tj;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('P15-08 검사 $mode')),
          body: KaraokeSearchScreen(
            load: (q) => load(mode, q),
            prepareRegistration: save,
            initialQuery: KaraokeQuery(
              brand,
              KaraokeKind.title,
              mode == 5 ? '이전' : '검사 곡',
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    final queue = await repository!.pending();
    if (mounted) {
      setState(() {
        saved = queue.length;
        status = '저장 요청 $saved개 · 취소/장애는 증가하면 안 됩니다';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P15-08 검색·등록 실기 검증')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '실제 검색·등록 화면과 SQLite를 사용합니다. 외부 응답/저장 장애만 합성하며 개인 앱 데이터와 서버는 건드리지 않습니다.',
          ),
          const SizedBox(height: 12),
          Text(status),
          const SizedBox(height: 12),
          for (final entry in const {
            1: '1. TJ 선택·취소 (저장 0)',
            2: '2. 금영 → TJ 찾기·취소 (저장 0)',
            3: '3. 검색 없음 → 직접 등록 (저장 +1)',
            4: '4. 외부 장애 (직접 등록 없음)',
            5: '5. 지연 중 최신 검색어 유지',
            6: '6. 저장 실패·메모 보존·같은 요청 재시도 (저장 +1)',
          }.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: OutlinedButton(
                onPressed: repository == null ? null : () => open(entry.key),
                child: Text(entry.value),
              ),
            ),
          const Text(
            '같은/다른 TJ 번호, 위조·만료 증명의 서버 검사는 PC 격리 통합 검사로 별도 확인합니다. 이 화면의 합성 결과를 실제 외부 조회로 간주하지 않습니다.',
          ),
        ],
      ),
    ),
  );
}
