import 'package:flutter/material.dart';

import '../theme/app_field_tokens.dart';

class AppMediumControlFrame extends StatelessWidget {
  const AppMediumControlFrame({
    super.key,
    required this.child,
    this.height = AppFieldTokens.mediumFieldHeight,
    this.width,
  });

  final Widget child;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final framed = SizedBox(height: height, child: child);
    if (width == null) {
      return framed;
    }
    return SizedBox(width: width, child: framed);
  }
}

class AppMediumLabeledControl extends StatelessWidget {
  const AppMediumLabeledControl({
    super.key,
    required this.label,
    required this.child,
    this.width,
    this.height = AppFieldTokens.mediumFieldHeight,
    this.gap = 4,
    this.labelStyle,
  });

  final String label;
  final Widget child;
  final double? width;
  final double height;
  final double gap;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(label, style: labelStyle ?? Theme.of(context).textTheme.bodySmall);
    final control = AppMediumControlFrame(height: height, width: width, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelWidget,
        SizedBox(height: gap),
        control,
      ],
    );
  }
}

class AppMediumTextField extends StatelessWidget {
  const AppMediumTextField({
    super.key,
    required this.controller,
    required this.readOnly,
    this.keyboardType,
    this.textAlign = TextAlign.right,
    this.textAlignVertical = TextAlignVertical.center,
    this.style,
    this.hintText,
    this.hintStyle,
    this.borderRadius = AppFieldTokens.mediumFieldRadius,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  });

  final TextEditingController controller;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final TextAlignVertical textAlignVertical;
  final TextStyle? style;
  final String? hintText;
  final TextStyle? hintStyle;
  final BorderRadius borderRadius;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? Theme.of(context).textTheme.bodySmall;
    final outlineColor = Theme.of(context).colorScheme.outline.withValues(alpha: 0.45);
    final fillColor = Theme.of(context).colorScheme.surface;
    final innerShadeTop = Colors.white.withValues(alpha: 0.55);
    final innerShadeBottom = Colors.black.withValues(alpha: 0.035);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: fillColor,
        border: Border.all(color: outlineColor),
        boxShadow: [
          BoxShadow(
            color: innerShadeTop,
            blurRadius: 2,
            spreadRadius: -1,
            offset: const Offset(0, 1),
            blurStyle: BlurStyle.inner,
          ),
          BoxShadow(
            color: innerShadeBottom,
            blurRadius: 1.2,
            spreadRadius: -1,
            offset: const Offset(0, -1),
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.center,
        child: TextField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType,
          maxLines: 1,
          textAlign: textAlign,
          textAlignVertical: textAlignVertical,
          style: effectiveStyle,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: hintStyle,
            isDense: true,
            border: InputBorder.none,
            contentPadding: contentPadding,
          ),
        ),
      ),
    );
  }
}

class AppMediumDropdown<T> extends StatelessWidget {
  const AppMediumDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.style,
    this.icon,
    this.hint,
    this.borderRadius = AppFieldTokens.mediumFieldRadius,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 10),
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final TextStyle? style;
  final Widget? icon;
  final Widget? hint;
  final BorderRadius borderRadius;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    final outlineColor = Theme.of(context).colorScheme.outline.withValues(alpha: 0.45);
    final fillColor = Theme.of(context).colorScheme.surface;
    final innerShadeTop = Colors.white.withValues(alpha: 0.55);
    final innerShadeBottom = Colors.black.withValues(alpha: 0.035);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: fillColor,
        border: Border.all(color: outlineColor),
        boxShadow: [
          BoxShadow(
            color: innerShadeTop,
            blurRadius: 2,
            spreadRadius: -1,
            offset: const Offset(0, 1),
            blurStyle: BlurStyle.inner,
          ),
          BoxShadow(
            color: innerShadeBottom,
            blurRadius: 1.2,
            spreadRadius: -1,
            offset: const Offset(0, -1),
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: Padding(
          padding: contentPadding,
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            alignment: AlignmentDirectional.centerEnd,
            style: style,
            icon: icon,
            hint: hint,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
