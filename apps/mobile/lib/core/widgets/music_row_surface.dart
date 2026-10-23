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
    this.flat = false,
    this.padding,
    super.key,
  });

  final Widget child;
  final double minHeight;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final bool compact;
  final bool flat;
  final EdgeInsetsGeometry? padding;

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
        color: flat
            ? Colors.transparent
            : Theme.of(context).colorScheme.surface,
        shape: flat
            ? Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              )
            : RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding:
                  padding ??
                  (flat
                      ? const EdgeInsets.symmetric(vertical: 14)
                      : const EdgeInsets.all(
                          AppDimensions.compactSongRowPadding,
                        )),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
