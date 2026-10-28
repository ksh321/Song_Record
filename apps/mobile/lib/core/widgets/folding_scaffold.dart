import 'package:flutter/material.dart';

/// Reorder mode hides the heading only when entered at the top of a list.
/// Selection mode keeps the original geometry so the pressed row stays put.
class FoldingScaffold extends StatelessWidget {
  const FoldingScaffold({
    super.key,
    required this.collapsed,
    this.appBar,
    required this.body,
  });
  final bool collapsed;
  final PreferredSizeWidget? appBar;
  final Widget body;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: collapsed ? 0 : 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250),
    curve: Curves.easeOut,
    builder: (context, factor, _) => Scaffold(
      appBar: appBar == null
          ? null
          : PreferredSize(
              preferredSize: Size.fromHeight(
                appBar!.preferredSize.height * factor,
              ),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight:
                      appBar!.preferredSize.height +
                      MediaQuery.paddingOf(context).top,
                  maxHeight:
                      appBar!.preferredSize.height +
                      MediaQuery.paddingOf(context).top,
                  child: Opacity(opacity: factor, child: appBar),
                ),
              ),
            ),
      body: body,
    ),
  );
}
