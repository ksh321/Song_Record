import 'package:flutter/material.dart';
import 'package:song_record/app/app_shell.dart';
import 'package:song_record/app/app_tab.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/settings/settings_screen.dart';
import 'package:song_record/routing/app_routes.dart';
import 'package:song_record/routing/tab_navigation.dart';

void main() => runApp(const NavigationPreviewApp());

/// Standalone navigation fixture. Does not open a DB, network or recorder.
class NavigationPreviewApp extends StatelessWidget {
  const NavigationPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark(),
      routes: {
        AppRoutes.settings: (_) =>
            const SettingsScreen(showDevelopmentTools: false),
      },
      home: AppShell(
        recorderGateway: const MethodChannelRecorderGateway(),
        tabBuilder: (context, tab) => NavigationPreviewList(tab: tab),
      ),
    );
  }
}

class NavigationPreviewList extends StatelessWidget {
  const NavigationPreviewList({required this.tab, super.key});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    final navigation = TabNavigation.of(context);
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('탐색 검증용 샘플 · 실제 곡·녹음 데이터가 아닙니다.'),
        ),
        Text('선택: ${navigation.selectedPlaylistId ?? "없음"}'),
        Expanded(
          child: ListView.builder(
            key: PageStorageKey('preview-list-${tab.name}'),
            primary: false,
            itemExtent: 72,
            itemCount: 60,
            itemBuilder: (context, index) => ListTile(
              key: ValueKey('preview-item-${tab.name}-$index'),
              title: Text('${tab.label} 샘플 ${index + 1}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => navigation.openPage<void>(
                title: '${tab.label} 샘플 ${index + 1} 상세',
                builder: (_) => const _PreviewDetail(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewDetail extends StatelessWidget {
  const _PreviewDetail();

  @override
  Widget build(BuildContext context) {
    final navigation = TabNavigation.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('상세에서 탭과 설정을 다녀온 뒤 뒤로가기를 확인하세요.'),
        const SizedBox(height: 16),
        Text('선택: ${navigation.selectedPlaylistId ?? "없음"}'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            final selected = await navigation.openPage<String>(
              title: '플레이리스트 선택 미리보기',
              builder: (_) => const _PreviewPicker(),
            );
            if (!context.mounted || selected == null) return;
            navigation.selectPlaylist(selected);
          },
          child: const Text('플레이리스트 선택'),
        ),
      ],
    );
  }
}

class _PreviewPicker extends StatelessWidget {
  const _PreviewPicker();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final id in ['샘플 A', '샘플 B'])
          ListTile(title: Text(id), onTap: () => Navigator.of(context).pop(id)),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('취소'),
        ),
      ],
    );
  }
}
