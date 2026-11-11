import 'browser_url_stub.dart' if (dart.library.html) 'browser_url_web.dart'
    as impl;

bool removeQueryParametersFromCurrentUrl(Set<String> names) {
  return impl.removeQueryParametersFromCurrentUrl(names);
}
