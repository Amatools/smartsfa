// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> convertPngBytesToWebp(Uint8List pngBytes) async {
  final blob = html.Blob(<dynamic>[pngBytes], 'image/png');
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  final image = html.ImageElement();
  final completer = Completer<void>();

  late final StreamSubscription<html.Event> loadSub;
  late final StreamSubscription<html.Event> errorSub;

  loadSub = image.onLoad.listen((_) async {
    await loadSub.cancel();
    await errorSub.cancel();
    completer.complete();
  });

  errorSub = image.onError.listen((_) async {
    await loadSub.cancel();
    await errorSub.cancel();
    completer.completeError(
      StateError('Falha ao carregar imagem para converter para WebP.'),
    );
  });

  image.src = objectUrl;

  try {
    await completer.future;

    final width = image.naturalWidth;
    final height = image.naturalHeight;
    if (width <= 0 || height <= 0) {
      return null;
    }

    final canvas = html.CanvasElement(width: width, height: height);
    final context = canvas.context2D;
    context.drawImage(image, 0, 0);

    final dataUrl = canvas.toDataUrl('image/webp', 0.9);
    if (!dataUrl.startsWith('data:image/webp')) {
      return null;
    }

    final commaIndex = dataUrl.indexOf(',');
    if (commaIndex == -1 || commaIndex >= dataUrl.length - 1) {
      return null;
    }

    final encoded = dataUrl.substring(commaIndex + 1);
    final decoded = base64Decode(encoded);
    return decoded.isEmpty ? null : Uint8List.fromList(decoded);
  } catch (_) {
    return null;
  } finally {
    html.Url.revokeObjectUrl(objectUrl);
  }
}
