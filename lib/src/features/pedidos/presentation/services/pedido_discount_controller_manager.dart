import 'package:flutter/widgets.dart';

import '../../../../core/models/pedido.dart';

/// Owns the lifecycle of the per-item, per-discount-slot [TextEditingController]s
/// used by the inline point-discount fields in the pedido item editor, plus a
/// small "apply revision" counter per item used to detect stale async discount
/// applications (see callers of `bumpApplyRevision`/`isRevisionCurrent`).
///
/// Extracted from `_PedidoInlineEditorState` to isolate controller
/// create/reuse/dispose bookkeeping from the surrounding business logic and
/// widget-building code.
class PedidoDiscountControllerManager {
  final Map<String, List<TextEditingController>> _controllersByItemId =
      <String, List<TextEditingController>>{};
  final Map<String, int> _applyRevisionByItemId = <String, int>{};

  void disposeAll() {
    for (final controllers in _controllersByItemId.values) {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
    _controllersByItemId.clear();
    _applyRevisionByItemId.clear();
  }

  void disposeForItem(String itemId) {
    final controllers = _controllersByItemId.remove(itemId);
    _applyRevisionByItemId.remove(itemId);
    if (controllers == null) {
      return;
    }
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  /// Ensures there are exactly [slotCount] controllers registered for [item],
  /// creating new ones (seeded from `item.appliedDiscountPercents`) or
  /// disposing surplus ones as needed. Returns the (possibly mutated) list.
  List<TextEditingController> ensureControllersForItem(
    PedidoItem item,
    int slotCount,
  ) {
    final safeSlots = slotCount < 0 ? 0 : slotCount;
    final existing =
        _controllersByItemId[item.id] ?? <TextEditingController>[];

    if (safeSlots == 0) {
      for (final controller in existing) {
        controller.dispose();
      }
      _controllersByItemId[item.id] = <TextEditingController>[];
      return _controllersByItemId[item.id]!;
    }

    while (existing.length < safeSlots) {
      final index = existing.length;
      final initial = index < item.appliedDiscountPercents.length
          ? item.appliedDiscountPercents[index]
          : 0;
      existing.add(
        TextEditingController(
          text: initial <= 0
              ? ''
              : initial
                    .toStringAsFixed(initial % 1 == 0 ? 0 : 2)
                    .replaceAll('.', ','),
        ),
      );
    }

    while (existing.length > safeSlots) {
      existing.removeLast().dispose();
    }

    _controllersByItemId[item.id] = existing;
    return existing;
  }

  void setControllersForItem(
    String itemId,
    List<TextEditingController> controllers,
  ) {
    _controllersByItemId[itemId] = controllers;
  }

  /// Bumps and returns the new "apply revision" for [itemId], used to detect
  /// whether a later, overlapping async discount-apply call has superseded
  /// an in-flight one.
  int bumpApplyRevision(String itemId) {
    final next = (_applyRevisionByItemId[itemId] ?? 0) + 1;
    _applyRevisionByItemId[itemId] = next;
    return next;
  }

  bool isApplyRevisionCurrent(String itemId, int revision) {
    return (_applyRevisionByItemId[itemId] ?? 0) == revision;
  }
}
