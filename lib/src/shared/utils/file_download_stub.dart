import 'dart:typed_data';

Future<void> downloadFileBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  throw UnsupportedError(
    'Download direto de arquivo nao suportado nesta plataforma.',
  );
}