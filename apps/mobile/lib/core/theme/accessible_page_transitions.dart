import 'package:flutter/material.dart';

/// Keep platform transitions normally; omit visual motion when requested.
class AccessiblePageTransitions extends PageTransitionsBuilder {
  const AccessiblePageTransitions(this.platformBuilder);

  final PageTransitionsBuilder platformBuilder;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation) {
      return child;
    }
    return platformBuilder.buildTransitions(
      route, context, animation, secondaryAnimation, child,
    );
  }
}
