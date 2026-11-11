// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

bool removeQueryParametersFromCurrentUrl(Set<String> names) {
  if (names.isEmpty) {
    return false;
  }

  final uri = Uri.base;
  final nextParams = Map<String, String>.from(uri.queryParameters)
    ..removeWhere((key, _) => names.contains(key));

  final nextUri = uri.replace(
    queryParameters: nextParams.isEmpty ? null : nextParams,
  );

  html.window.history.replaceState(null, html.document.title, nextUri.toString());
  return true;
}
