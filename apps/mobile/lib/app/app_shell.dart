import 'package:flutter/material.dart';
import 'package:song_record/app/app_tab.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/content_state.dart';
import 'package:song_record/core/widgets/song_discovery_sheet.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';
import 'package:song_record/features/recorder/recorder_panel.dart';
import 'package:song_record/routing/app_routes.dart';
import 'package:song_record/routing/tab_navigation.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.recorderGateway,
    this.tabBuilder,
    this.searchBuilder,
    super.key,
  });

  final RecorderGateway recorderGateway;
  final WidgetBuilder? searchBuilder;

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
  bool _settingsOpen = false;

  void _selectTab(int index) {
    final tab = AppTab.values[index];
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
    if (_settingsOpen) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _settingsOpen = true;
    try {
      await Navigator.of(context).pushNamed<void>(AppRoutes.settings);
    } finally {
      _settingsOpen = false;
    }
  }

  Future<void> _findSong() async {
    final result = await showSongDiscoverySheet(context: context);
    if (!mounted || result == null) {
      return;
    }
    switch (result.destination) {
      case SongDiscoveryDestination.charts:
        _selectTab(AppTab.charts.index);
      case SongDiscoveryDestination.search:
        _selectTab(AppTab.search.index);
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
                            _buildTab(tab),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
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
    if (tab == AppTab.search && widget.searchBuilder != null) {
      return widget.searchBuilder!(context);
    }
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
          ContentState(
            phase: ContentPhase.waiting,
            title: tab.introduction,
            message: '기능을 준비하고 있어요.',
          ),
          if (tab == AppTab.songs)
            FilledButton(onPressed: _findSong, child: const Text('새 곡 찾기')),
        ],
      ],
    );
  }
}
