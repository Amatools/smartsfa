import 'dart:typed_data';

import 'web_logo_webp_converter_stub.dart'
    if (dart.library.html) 'web_logo_webp_converter_web.dart'
    as impl;

Future<Uint8List?> convertPngBytesToWebp(Uint8List pngBytes) {
  return impl.convertPngBytesToWebp(pngBytes);
}
