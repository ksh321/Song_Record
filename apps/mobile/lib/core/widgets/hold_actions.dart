import 'package:flutter/material.dart';

/// Shared long-press menu. Mutations still use their existing confirmation flow.
Future<String?> showHoldActions(
  BuildContext context, {
  required String title,
  required String deleteLabel,
  bool reorder = false,
}) => showDialog<String>(
  context: context,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (reorder)
            ListTile(
              title: const Text('순서 변경'),
              onTap: () => Navigator.pop(context, 'reorder'),
            ),
          ListTile(
            title: Text(deleteLabel),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
          ),
        ],
      ),
    ),
  ),
);
