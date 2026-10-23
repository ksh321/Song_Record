import 'package:flutter/material.dart';
import 'package:song_record/app/app_tab.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/content_state.dart';
import 'package:song_record/core/widgets/song_discovery_sheet.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recorder_panel.dart';
import 'package:song_record/routing/app_routes.dart';
import 'package:song_record/routing/tab_navigation.dart';

import '../core/widgets/app_icon.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.recorderGateway,
    this.tabBuilder,
    this.settingsBuilder,
    this.searchBuilder,
    this.chartBuilder,
    this.manualBuilder,
    this.songsBuilder,
    this.recordingBuilder,
    this.playlistsBuilder,
    super.key,
  });

  final RecorderGateway recorderGateway;
  final WidgetBuilder? searchBuilder;
  final WidgetBuilder? settingsBuilder;
  final WidgetBuilder? recordingBuilder;
  final WidgetBuilder? playlistsBuilder;
  final WidgetBuilder? chartBuilder;
  final WidgetBuilder? manualBuilder;
  final Widget Function(BuildContext, VoidCallback)? songsBuilder;

  /// Allows a separate preview/test to exercise future tab bodies.
  /// Production uses the existing placeholders and single recorder panel.
  final Widget Function(BuildContext context, AppTab tab)? tabBuilder;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _selectedTab = AppTab.songs;
  final Set<AppTab> _visitedTabs = {AppTab.songs};
  final _tabKeys = {
    for (final tab in AppTab.values) tab: GlobalKey<TabNavigatorState>(),
  };
  final Set<AppTab> _settingsTabs = {};

  void _selectTab(int index) {
    final tab = AppTab.values[index];
    if (_settingsTabs.contains(_selectedTab) &&
        !(_tabKeys[_selectedTab]?.currentState?.allowsTabChange ?? true)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (tab == _selectedTab) {
      _tabKeys[tab]?.currentState?.popToRoot();
      return;
    }
    setState(() {
      _selectedTab = tab;
      _visitedTabs.add(tab);
    });
  }

  Future<void> _openSettings() async {
    final settingsTab = _selectedTab;
    if (_settingsTabs.contains(settingsTab)) {
      _tabKeys[settingsTab]?.currentState?.returnToSettings();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _settingsTabs.add(settingsTab);
    try {
      final builder = widget.settingsBuilder;
      if (builder == null) {
        await Navigator.of(context).pushNamed<void>(AppRoutes.settings);
      } else {
        await _tabKeys[settingsTab]?.currentState?.openScreen<void>(
          builder,
          name: AppRoutes.settings,
        );
      }
    } finally {
      _settingsTabs.remove(settingsTab);
    }
  }

  Future<void> _findSong(BuildContext context) async {
    final result = await showSongDiscoverySheet(context: context);
    if (!mounted || !context.mounted || result == null) {
      return;
    }
    switch (result.destination) {
      case SongDiscoveryDestination.charts:
        _selectTab(AppTab.charts.index);
      case SongDiscoveryDestination.search:
        _selectTab(AppTab.search.index);
      case SongDiscoveryDestination.manual:
        final builder = widget.manualBuilder;
        if (builder != null) {
          await Navigator.of(context)
              .push<void>(MaterialPageRoute(builder: builder));
        }
      case SongDiscoveryDestination.mySongs:
        break; // Only offered by callers with a playlist context.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
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
                    ? TabNavigator(
                        key: _tabKeys[tab],
                        tab: tab,
                        active: tab == _selectedTab,
                        openSettings: _openSettings,
                        rootBuilder: (context) =>
                            widget.tabBuilder?.call(context, tab) ??
                            _buildTab(tab, context),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        child: NavigationBar(
          animationDuration:
              MediaQuery.of(context).disableAnimations ||
                  MediaQuery.of(context).accessibleNavigation
              ? Duration.zero
              : null,
          selectedIndex: _selectedTab.index,
          onDestinationSelected: _selectTab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelPadding: EdgeInsets.zero,
          destinations: [
            for (final tab in AppTab.values)
              NavigationDestination(
                key: ValueKey('tab-${tab.name}'),
                icon: AppIcon(tab.icon, size: 22),
                selectedIcon: AppIcon(tab.selectedIcon, size: 22),
                label: tab.label,
                tooltip: tab.label,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(AppTab tab, BuildContext context) {
    if (tab == AppTab.songs && widget.songsBuilder != null) {
      return widget.songsBuilder!(context, () => _findSong(context));
    }
    if (tab == AppTab.charts && widget.chartBuilder != null) {
      return widget.chartBuilder!(context);
    }
    if (tab == AppTab.search && widget.searchBuilder != null) {
      return widget.searchBuilder!(context);
    }
    if (tab == AppTab.recording && widget.recordingBuilder != null) {
      return widget.recordingBuilder!(context);
    }
    if (tab == AppTab.playlists && widget.playlistsBuilder != null) {
      return widget.playlistsBuilder!(context);
    }
    return ListView(
      key: PageStorageKey('page-${tab.name}'),
      primary: false,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (tab == AppTab.recording)
          // Keep this single panel mounted when navigating to another tab or
          // settings. The native service remains the recording state owner.
          RecorderPanel(gateway: widget.recorderGateway, diagnostics: false)
        else ...[
          ContentState(
            phase: ContentPhase.waiting,
            title: tab.introduction,
            message: '기능을 준비하고 있어요.',
          ),
          if (tab == AppTab.songs)
            FilledButton(
              onPressed: () => _findSong(context),
              child: const Text('새 곡 찾기'),
            ),
        ],
      ],
    );
  }
}
