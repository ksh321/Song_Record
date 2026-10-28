import 'package:flutter/material.dart';

import 'app_icon.dart';

/// Shared outline treatment for feature entry points in either appearance.
class FeatureIcon extends StatelessWidget {
  const FeatureIcon(
    this.icon, {
    super.key,
    this.size = 40,
    this.selected = false,
  });

  final IconData icon;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: accent, width: selected ? 2 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AppIcon(icon, size: size * .58, color: accent),
    );
  }
}
