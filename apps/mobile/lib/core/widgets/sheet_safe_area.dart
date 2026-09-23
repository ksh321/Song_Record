import 'package:flutter/material.dart';

/// Modal sheets do not inherit Scaffold's keyboard resizing. Reserve the
/// keyboard area outside the scroll viewport so its final action stays usable.
class SheetSafeArea extends StatelessWidget {
  const SheetSafeArea({required this.child, this.top = false, super.key});

  final Widget child;
  final bool top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(top: top, child: child),
  );
}
