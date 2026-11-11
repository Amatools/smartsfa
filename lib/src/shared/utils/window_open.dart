import 'window_open_stub.dart'
    if (dart.library.html) 'window_open_web.dart' as impl;

bool openUrlInNewTab(String url) {
  return impl.openUrlInNewTab(url);
}

bool closeCurrentBrowserWindow() {
  return impl.closeCurrentBrowserWindow();
}
