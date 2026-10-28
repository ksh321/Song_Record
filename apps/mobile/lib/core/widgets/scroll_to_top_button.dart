import 'package:flutter/material.dart';

/// Shared by chart and local library views.
class ScrollToTopButton extends StatelessWidget {
  const ScrollToTopButton({required this.controller, super.key});
  final ScrollController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => !controller.hasClients || controller.offset < 64
        ? const SizedBox.shrink()
        : IconButton.filled(
            tooltip: '맨 위로',
            onPressed: () {
              if (MediaQuery.disableAnimationsOf(context)) {
                controller.jumpTo(0);
              } else {
                controller.animateTo(
                  0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
  );
}

/// Owns the scroll position and overlays the same control on a scrollable page.
class ScrollToTopView extends StatefulWidget {
  const ScrollToTopView({required this.builder, super.key});
  final Widget Function(ScrollController controller) builder;
  @override
  State<ScrollToTopView> createState() => _ScrollToTopViewState();
}

class _ScrollToTopViewState extends State<ScrollToTopView> {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: widget.builder(scroll)),
      Positioned(
        right: 16,
        bottom: 16,
        child: ScrollToTopButton(controller: scroll),
      ),
    ],
  );
}
