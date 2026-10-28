import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'feature_icon.dart';

/// Final, computed UI03 CSS values. Shared by every product screen.
abstract final class AppLayout {
  static const bodyPadding = EdgeInsets.fromLTRB(20, 4, 20, 22);
  static const gap = 14.0;
  static Color selection(BuildContext context) => Color.alphaBlend(
    Theme.of(context).colorScheme.primary.withValues(
      alpha: Theme.of(context).brightness == Brightness.light ? .14 : .25,
    ),
    Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : const Color(0xff292929),
  );
}

class AppSearchField extends StatelessWidget {
  const AppSearchField({
    required this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.fieldKey,
    super.key,
  });
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged, onSubmitted;
  final Key? fieldKey;
  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    textInputAction: TextInputAction.search,
    style: const TextStyle(fontSize: 13, height: 1.5),
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const AppIcon(Icons.search, size: 18),
      prefixIconConstraints: const BoxConstraints(minWidth: 41),
      constraints: const BoxConstraints(minHeight: 49),
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(0, 14, 13, 14),
    ),
  );
}

class AppBrandTabs<T> extends StatelessWidget {
  const AppBrandTabs({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
    ),
    child: Row(
      children: [
        for (final entry in options.entries)
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Semantics(
              selected: selected == entry.key,
              button: true,
              child: InkWell(
                onTap: () => onChanged(entry.key),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 52,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.fromLTRB(3, 10, 3, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 3,
                        color: selected == entry.key
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: selected == entry.key
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: selected == entry.key
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class AppOptions<T> extends StatelessWidget {
  const AppOptions({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.pills = false,
    this.equalWidth = false,
    super.key,
  });
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool pills;
  final bool equalWidth;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(MapEntry<T, String> entry) {
      final active = entry.key == selected;
      return Semantics(
        button: true,
        selected: active,
        child: Material(
          color: active
              ? AppLayout.selection(context)
              : pills
              ? scheme.surface
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(pills ? 20 : 8),
            side: pills
                ? BorderSide(
                    color: active
                        ? Color.alphaBlend(
                            scheme.primary.withValues(alpha: .45),
                            scheme.outline,
                          )
                        : scheme.outline,
                  )
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onChanged(entry.key),
            child: Container(
              constraints: BoxConstraints(minHeight: pills ? 44 : 44),
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: pills ? 15 : 8,
                vertical: 7,
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  fontWeight: !pills && active
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (pills) {
      if (equalWidth) {
        return Row(
          children: [
            for (final entry in options.entries) ...[
              if (entry.key != options.keys.first) const SizedBox(width: 7),
              Expanded(child: option(entry)),
            ],
          ],
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.entries
            .map((e) => IntrinsicWidth(child: option(e)))
            .toList(),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final entry in options.entries) ...[
            if (entry.key != options.keys.first) const SizedBox(width: 4),
            Expanded(child: option(entry)),
          ],
        ],
      ),
    );
  }
}

class AppNavigationIndicator extends ShapeBorder {
  const AppNavigationIndicator();
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  ShapeBorder scale(double t) => this;
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: rect.width.clamp(0, 50),
            height: 31,
          ),
          const Radius.circular(18),
        ),
      );
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}

class AppCompactAction extends StatelessWidget {
  const AppCompactAction({
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
    this.compact = false,
    super.key,
  });
  final String label;
  final bool compact;
  final VoidCallback? onPressed;
  final IconData icon;
  @override
  Widget build(BuildContext context) => compact
      ? IconButton.filled(
          onPressed: onPressed,
          tooltip: label,
          icon: AppIcon(icon, size: 20),
          style: IconButton.styleFrom(fixedSize: const Size(42, 42)),
        )
      : FilledButton.icon(
          onPressed: onPressed,
          icon: AppIcon(icon, size: 16),
          label: Text(label),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            textStyle: const TextStyle(
              fontFamily: 'ReferenceKR',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.55,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
}

class AppPickerField extends StatelessWidget {
  const AppPickerField({
    required this.label,
    required this.value,
    required this.onPressed,
    this.trailingLabel,
    super.key,
  });
  final String label, value;
  final String? trailingLabel;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Semantics(
      button: true,
      label: '$label: $value',
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        value,
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                    ],
                  ),
                ),
                const AppIcon(Icons.chevron_right, size: 18),
                if (trailingLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      trailingLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(14),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class AppLabeledField extends StatelessWidget {
  const AppLabeledField({
    required this.label,
    required this.controller,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
    this.onChanged,
    this.fieldKey,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final int minLines, maxLines;
  final ValueChanged<String>? onChanged;
  final Key? fieldKey;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      Semantics(
        label: label,
        child: TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          minLines: minLines,
          maxLines: maxLines,
          onChanged: onChanged,
          style: const TextStyle(
            fontFamily: 'ReferenceKR',
            fontSize: 13,
            height: 1.6,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            constraints: BoxConstraints(minHeight: minLines == 1 ? 49 : 104),
          ),
        ),
      ),
    ],
  );
}

class AppLabeledFormField extends StatelessWidget {
  const AppLabeledFormField({
    required this.label,
    required this.controller,
    required this.validator,
    this.readOnly = false,
    this.maxLines = 1,
    this.fieldKey,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final bool readOnly;
  final int maxLines;
  final Key? fieldKey;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      Semantics(
        label: label,
        child: TextFormField(
          key: fieldKey,
          controller: controller,
          validator: validator,
          readOnly: readOnly,
          maxLines: maxLines,
          style: const TextStyle(
            fontFamily: 'ReferenceKR',
            fontSize: 13,
            height: 1.6,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            constraints: BoxConstraints(minHeight: maxLines == 1 ? 49 : 104),
          ),
        ),
      ),
    ],
  );
}

/// HTML .item geometry shared by settings, personalization and recording links.
class AppFeatureRow extends StatelessWidget {
  const AppFeatureRow({
    required this.title,
    required this.icon,
    this.subtitle,
    this.onTap,
    this.grouped = true,
    super.key,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool grouped;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: grouped ? 66 : 78),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: grouped ? 12 : 16,
          ),
          child: Row(
            children: [
              FeatureIcon(icon, size: grouped ? 30 : 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: grouped ? 13 : 15,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: grouped ? 11 : 12,
                          height: 1.7,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const AppIcon(Icons.chevron_right, size: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Common reorder action in both playlist screens and both appearances.
class AppReorderAction extends StatelessWidget {
  const AppReorderAction({
    super.key,
    required this.onPressed,
    this.compact = false,
  });
  final VoidCallback? onPressed;
  final bool compact;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '순서 변경',
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        minimumSize: Size(compact ? 42 : 0, 40),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.unfold_more, size: 18),
          if (!compact) ...[const SizedBox(width: 4), const Text('순서 변경')],
        ],
      ),
    ),
  );
}
