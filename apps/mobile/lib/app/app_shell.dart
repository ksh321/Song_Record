import 'package:flutter/material.dart';
import 'package:song_record/app/app_tab.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recorder_panel.dart';
import 'package:song_record/routing/app_routes.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.recorderGateway, super.key});

  final RecorderGateway recorderGateway;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _selectedTab = AppTab.songs;
  final Set<AppTab> _visitedTabs = {AppTab.songs};
  bool _settingsOpen = false;

  void _selectTab(int index) {
    final tab = AppTab.values[index];
    if (tab == _selectedTab) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedTab = tab;
      _visitedTabs.add(tab);
    });
  }

  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _settingsOpen = true);
    try {
      await Navigator.of(context).pushNamed<void>(AppRoutes.settings);
    } finally {
      if (mounted) setState(() => _settingsOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedTab.label),
        actions: [
          IconButton(
            key: const ValueKey('open-settings'),
            tooltip: '설정',
            onPressed: _settingsOpen ? null : _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: IndexedStack(
          index: _selectedTab.index,
          sizing: StackFit.expand,
          children: [
            for (final tab in AppTab.values)
              ExcludeFocus(
                key: ValueKey(tab),
                excluding: tab != _selectedTab,
                child: TickerMode(
                  enabled: tab == _selectedTab,
                  // Open once on first visit. In particular, startup does not
                  // create the recorder or request microphone permissions.
                  child: _visitedTabs.contains(tab)
                      ? _buildTab(tab)
                      : const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedTab.index,
          onDestinationSelected: _selectTab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelPadding: EdgeInsets.zero,
          destinations: [
            for (final tab in AppTab.values)
              NavigationDestination(
                key: ValueKey('tab-${tab.name}'),
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
                tooltip: tab.label,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(AppTab tab) {
    return ListView(
      key: PageStorageKey('page-${tab.name}'),
      primary: false,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (tab == AppTab.recording)
          // Keep this single panel mounted when navigating to another tab or
          // settings. The native service remains the recording state owner.
          RecorderPanel(gateway: widget.recorderGateway)
        else ...[
          const SizedBox(height: AppSpacing.lg),
          Icon(tab.icon, size: 48, color: AppColors.muted),
          const SizedBox(height: AppSpacing.lg),
          Text(
            tab.introduction,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            '기능을 준비하고 있어요.',
            textAlign: TextAlign.center,
            style: AppTypography.supporting,
          ),
        ],
      ],
    );
  }
}
