import 'package:flutter/material.dart';

mixin MountedStateMixin<T extends StatefulWidget> on State<T> {
  void setStateIfMounted(VoidCallback stateUpdater) {
    if (!mounted) {
      return;
    }
    setState(stateUpdater);
  }

  void runIfMounted(VoidCallback action) {
    if (!mounted) {
      return;
    }
    action();
  }
}
