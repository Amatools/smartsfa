import 'package:flutter/material.dart';

class ProductEditorCompactTab extends StatelessWidget {
  const ProductEditorCompactTab({
    super.key,
    required this.children,
    this.maxWidth = double.infinity,
  });

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    if (maxWidth.isFinite) {
      return Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: content,
        ),
      );
    }

    return SizedBox(width: double.infinity, child: content);
  }
}
