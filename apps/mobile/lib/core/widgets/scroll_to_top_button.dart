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
