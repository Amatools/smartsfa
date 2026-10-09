import 'dart:typed_data';

import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart' as impl;

Future<void> downloadFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  return impl.downloadFileBytes(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
}