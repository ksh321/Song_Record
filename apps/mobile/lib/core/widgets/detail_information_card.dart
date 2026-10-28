import 'package:flutter/material.dart';

import 'ui_controls.dart';

/// Shared presentation for saved song and recording information.
class DetailInformationCard extends StatelessWidget {
  const DetailInformationCard({
    required this.title,
    required this.fields,
    this.action,
    super.key,
  });
  final String title;
  final List<(String, String)> fields;
  final Widget? action;
  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
            ?action,
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, size) {
            final columns =
                size.maxWidth >= 260 &&
                MediaQuery.textScalerOf(context).scale(14) <= 21;
            Widget field((String, String) value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.$1,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  value.$2,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
            );
            if (!columns) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    field(fields[i]),
                  ],
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 24,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    Expanded(child: field(fields[i])),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
}
