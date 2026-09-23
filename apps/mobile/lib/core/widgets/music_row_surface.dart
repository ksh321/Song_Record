import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_tokens.dart';

/// Shared row surface: minimum height, keyboard focus and full-row hit target.
class MusicRowSurface extends StatelessWidget {
  const MusicRowSurface({
    required this.child,
    required this.minHeight,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.compact = false,
    super.key,
  });

  final Widget child;
  final double minHeight;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      compact ? AppDimensions.fieldRadius : AppDimensions.listCardRadius,
    );
    return Semantics(
      button: true,
      enabled: enabled && onTap != null,
      selected: selected,
      child: Material(
        color: compact ? AppColors.compactRowBackground : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: compact ? AppColors.compactRowBorder : AppColors.line,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.all(
                AppDimensions.compactSongRowPadding,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
