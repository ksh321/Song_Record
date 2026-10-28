import 'package:flutter/material.dart';
import 'package:song_record/app/app_tab.dart';

import '../core/theme/app_appearance.dart';
import '../core/widgets/app_icon.dart';
import '../core/widgets/folding_scaffold.dart';

/// Navigation context for one tab, retained only for this shell's lifetime.
/// This is UI selection, not account data or process-death restoration.
class TabNavigation extends ChangeNotifier {
  TabNavigation._(this._openSettings);

  final VoidCallback _openSettings;
  void openSettings() => _openSettings();
  final _navigatorKey = GlobalKey<NavigatorState>();
  String? _selectedPlaylistId;
  String? _subtitle;
  bool _headerFolded = false;
  void foldHeader(bool value) {
    if (_headerFolded == value) return;
    _headerFolded = value;
    notifyListeners();
  }

  void updateHeaderSubtitle(String? value) {
    if (_subtitle == value) return;
    _subtitle = value;
    notifyListeners();
  }

  static TabNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TabScope>()?.notifier;

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

class _TabRouteObserver extends NavigatorObserver {
  Route<dynamic>? top;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    top = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    top = previousRoute;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (top == route) top = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (top == oldRoute) top = newRoute;
  }
}

class TabNavigatorState extends State<TabNavigator> {
  final _routes = _TabRouteObserver();
  bool get allowsTabChange =>
      _routes.top?.popDisposition != RoutePopDisposition.doNotPop;
  void returnToSettings() {
    if (!allowsTabChange) return;
    _navigation._navigatorKey.currentState?.popUntil(
      (route) => route.settings.name == '/settings' || route.isFirst,
    );
  }

  Future<T?> openScreen<T>(WidgetBuilder builder, {String? name}) =>
      _navigation._navigatorKey.currentState!.push<T>(
        MaterialPageRoute<T>(
          builder: builder,
          settings: RouteSettings(name: name),
        ),
      );

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
          observers: [_routes],
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
    return FoldingScaffold(
      collapsed:
          !showBack && (TabNavigation.maybeOf(context)?._headerFolded ?? false),
      appBar: AppBar(
        toolbarHeight:
            (MediaQuery.textScalerOf(context).scale(26) * 1.3 +
                    32 +
                    (!showBack &&
                            TabNavigation.maybeOf(context)?._subtitle != null
                        ? MediaQuery.textScalerOf(context).scale(12) * 1.55 + 6
                        : 0))
                .clamp(88, double.infinity),
        title: Tooltip(
          message: title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  letterSpacing: -1.1,
                ),
              ),
              if ((showBack ? null : TabNavigation.maybeOf(context)?._subtitle)
                  case final String subtitle) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.55,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                tooltip: '뒤로가기',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const AppIcon(Icons.arrow_back),
              )
            : null,
        actions: [
          const ThemeToggle(),
          IconButton(
            tooltip: '설정',
            onPressed: openSettings,
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              minimumSize: const Size(44, 44),
              maximumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const AppIcon(Icons.settings_outlined, size: 20),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: SafeArea(top: false, bottom: false, child: child),
    );
  }
}

/// A screen's existing observed data supplies presentation-only header text.
/// It neither starts a query nor alters any account state.
class TabHeaderSubtitle extends StatelessWidget {
  const TabHeaderSubtitle(this.text, {super.key});
  final String? text;
  @override
  Widget build(BuildContext context) {
    final navigation = TabNavigation.maybeOf(context);
    if (navigation != null && navigation._subtitle != text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && navigation._subtitle != text) {
          navigation.updateHeaderSubtitle(text);
        }
      });
    }
    return const SizedBox.shrink();
  }
}
