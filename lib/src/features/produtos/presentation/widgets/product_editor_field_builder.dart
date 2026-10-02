import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ProductEditorFieldBuilder = Widget Function(
  TextEditingController controller,
  String label, {
  required bool readOnly,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  int maxLines,
  TextAlign textAlign,
});
