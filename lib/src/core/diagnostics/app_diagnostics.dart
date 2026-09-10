import 'package:firebase_core/firebase_core.dart' show FirebaseException;

/// A single recorded diagnostic event: either a caught error/exception or
/// a plain informational note, kept only in memory for the current app
/// session so support can be given ("what really happened") without needing
/// any remote logging infrastructure.
class DiagnosticEntry {
  DiagnosticEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.details,
  });

  final DateTime timestamp;
  final String tag;
  final String message;
  final String? details;
}

/// In-memory ring buffer of recent diagnostic events plus a helper to turn
/// raw error objects into a short, human-readable line. This is the single
/// place the rest of the app should go through to record "something failed
/// in the background" (best-effort/self-healing paths) or to back a real
/// error dialog shown for a direct user action.
class AppDiagnostics {
  AppDiagnostics._();

  static const int _maxEntries = 100;
  static final List<DiagnosticEntry> _entries = [];

  /// Most recent entries first.
  static List<DiagnosticEntry> get entries => List.unmodifiable(_entries.reversed);

  static void clear() => _entries.clear();

  static void log({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final details = error == null
        ? null
        : <String>[
            describeError(error),
            if (stackTrace != null) '\n$stackTrace',
          ].join();

    _entries.add(
      DiagnosticEntry(
        timestamp: DateTime.now(),
        tag: tag,
        message: message,
        details: details,
      ),
    );

    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  /// Turns a raw error object into a short, human-readable line. Special
  /// cases [FirebaseException] (thrown by both Firebase Auth and
  /// Firestore) so its `code`/`message`/`plugin` are visible instead of a
  /// generic `Instance of '...'` toString().
  static String describeError(Object error) {
    if (error is FirebaseException) {
      final parts = <String>[
        if (error.plugin.isNotEmpty) '[${error.plugin}]',
        if (error.code.isNotEmpty) error.code,
        if ((error.message ?? '').isNotEmpty) error.message!,
      ];
      return parts.isEmpty ? error.toString() : parts.join(' - ');
    }

    return error.toString();
  }
}
