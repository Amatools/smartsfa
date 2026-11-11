// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

bool openUrlInNewTab(String url) {
  if (url.trim().isEmpty) {
    return false;
  }

  html.window.open(url, '_blank');
  return true;
}

bool closeCurrentBrowserWindow() {
  html.window.close();
  return true;
}
