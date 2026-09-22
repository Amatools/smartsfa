import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class AppShellConnectivityCoordinator {
  const AppShellConnectivityCoordinator();

  StreamSubscription<List<ConnectivityResult>> watchOnlineChanges({
    required Connectivity connectivity,
    required Future<void> Function() onOnline,
  }) {
    return connectivity.onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        return;
      }
      onOnline();
    });
  }

  Future<bool> hasConnection(Connectivity connectivity) async {
    final connectivityResults = await connectivity.checkConnectivity();
    return connectivityResults.contains(ConnectivityResult.none) == false;
  }
}
