import 'package:flutter/material.dart';

typedef ProductEditorFieldBuilder = Widget Function(
  TextEditingController controller,
  String label, {
  required bool readOnly,
  TextInputType? keyboardType,
  int maxLines,
  TextAlign textAlign,
});