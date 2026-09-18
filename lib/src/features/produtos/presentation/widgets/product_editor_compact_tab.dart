import 'package:flutter/material.dart';

class ProductEditorCompactTab extends StatelessWidget {
  const ProductEditorCompactTab({
    super.key,
    required this.children,
    this.maxWidth = 760,
  });

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(children: children),
      ),
    );
  }
}