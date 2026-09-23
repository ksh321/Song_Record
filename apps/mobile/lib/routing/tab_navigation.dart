import 'package:flutter/material.dart';
import 'package:song_record/app/app_tab.dart';
import 'package:song_record/core/theme/app_tokens.dart';

/// Navigation context for one tab, retained only for this shell's lifetime.
/// This is UI selection, not account data or process-death restoration.
class TabNavigation extends ChangeNotifier {
  TabNavigation._(this._openSettings);

  final VoidCallback _openSettings;
  final _navigatorKey = GlobalKey<NavigatorState>();
  String? _selectedPlaylistId;

  static TabNavigation of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_TabScope>();
    assert(scope != null, 'Use a context inside a TabNavigator.');
    return scope!.notifier!;
  }

  String? get selectedPlaylistId => _selectedPlaylistId;

  /// Call on an explicit selection; cancelling a picker must not call this.
  void selectPlaylist(String? id) {
    if (id == _selectedPlaylistId) return;
    _selectedPlaylistId = id;
    notifyListeners();
  }

  Future<T?> openPage<T>({
    required String title,
    required WidgetBuilder builder,
  }) {
    return _navigatorKey.currentState!.push<T>(
      MaterialPageRoute<T>(
        builder: (context) => _TabPage(
          title: title,
          showBack: true,
          openSettings: _openSettings,
          child: Builder(builder: builder),
        ),
      ),
    );
  }
}

class _TabScope extends InheritedNotifier<TabNavigation> {
  const _TabScope({required TabNavigation navigation, required super.child})
    : super(notifier: navigation);
}

/// Each mounted tab owns an independent Navigator and PageStorage history.
class TabNavigator extends StatefulWidget {
  const TabNavigator({
    required this.tab,
    required this.active,
    required this.rootBuilder,
    required this.openSettings,
    super.key,
  });

  final AppTab tab;
  final bool active;
  final WidgetBuilder rootBuilder;
  final VoidCallback openSettings;

  @override
  State<TabNavigator> createState() => TabNavigatorState();
}

class TabNavigatorState extends State<TabNavigator> {
  /// Close detail/picker routes without recreating the root or recorder.
  void popToRoot() {
    _navigation._navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  late final TabNavigation _navigation = TabNavigation._(
    () => widget.openSettings(),
  );

  @override
  void dispose() {
    _navigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _TabScope(
      navigation: _navigation,
      child: NavigatorPopHandler<Object?>(
        enabled: widget.active,
        onPopWithResult: (result) {
          // Inactive handlers can also receive a blocked outer pop callback.
          if (widget.active) {
            _navigation._navigatorKey.currentState!.pop(result);
          }
        },
        child: Navigator(
          key: _navigation._navigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => _TabPage(
              title: widget.tab.label,
              showBack: false,
              openSettings: () => widget.openSettings(),
              child: Builder(builder: widget.rootBuilder),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabPage extends StatelessWidget {
  const _TabPage({
    required this.title,
    required this.showBack,
    required this.openSettings,
    required this.child,
  });

  final String title;
  final bool showBack;
  final VoidCallback openSettings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: (MediaQuery.textScalerOf(context)
                    .scale(AppTypography.songDetailTitleSize) * 1.4 + 16)
            .clamp(kToolbarHeight, double.infinity).toDouble(),
        title: Tooltip(
          message: title,
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                tooltip: '뒤로가기',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        actions: [
          IconButton(
            tooltip: '설정',
            onPressed: openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(top: false, bottom: false, child: child),
    );
  }
}
