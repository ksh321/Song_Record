import 'package:flutter/material.dart';

import '../../routing/app_routes.dart';
import '../../routing/tab_navigation.dart';
import '../theme/app_appearance.dart';
import 'app_icon.dart';

/// The same page controls as the HTML header, with busy-route locks preserved.
AppBar appPageBar(
  BuildContext context, {
  Widget? title,
  Widget? leading,
  List<Widget>? actions,
  bool automaticallyImplyLeading = true,
  bool showSettings = true,
}) => AppBar(
  title: title,
  leading: leading,
  automaticallyImplyLeading: automaticallyImplyLeading,
  actions: [
    ...?actions,
    if (!(actions?.any((w) => w is ThemeToggle) ?? false)) const ThemeToggle(),
    if (showSettings)
      IconButton(
        tooltip: '설정',
        icon: const AppIcon(Icons.settings_outlined, size: 20),
        onPressed: !automaticallyImplyLeading
            ? null
            : () {
                if (ModalRoute.of(context)?.popDisposition ==
                    RoutePopDisposition.doNotPop) {
                  return;
                }
                final tabs = TabNavigation.maybeOf(context);
                if (tabs != null) {
                  tabs.openSettings();
                } else {
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pushNamed(AppRoutes.settings);
                }
              },
      ),
  ],
);
