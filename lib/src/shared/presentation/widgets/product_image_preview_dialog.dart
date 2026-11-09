import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/models/produto.dart';
import '../../../core/services/mobile_product_image_cache_service.dart';

Future<void> showProductImagePreviewDialog({
  required BuildContext context,
  required Produto produto,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) => _ProductImagePreviewDialog(produto: produto),
  );
}

class _ProductImagePreviewDialog extends StatefulWidget {
  const _ProductImagePreviewDialog({required this.produto});

  final Produto produto;

  @override
  State<_ProductImagePreviewDialog> createState() =>
      _ProductImagePreviewDialogState();
}

class _ProductImagePreviewDialogState
    extends State<_ProductImagePreviewDialog> {
  late Future<ProductImagePreviewPayload> _payloadFuture;

  @override
  void initState() {
    super.initState();
    _payloadFuture = ProductImagePreviewResolver.resolve(widget.produto);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.produto.descricao.trim().isEmpty
        ? 'Foto do produto'
        : widget.produto.descricao.trim();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<ProductImagePreviewPayload>(
                future: _payloadFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    );
                  }

                  final payload = snapshot.data;
                  if (payload == null) {
                    return _ImageFallback(
                      fallbackText: _initial(widget.produto.descricao),
                    );
                  }

                  final bytes = payload.bytes;
                  if (bytes != null && bytes.isNotEmpty) {
                    return _ZoomableImage(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    );
                  }

                  if (kIsWeb && payload.webRemoteUrl.isNotEmpty) {
                    return _ZoomableImage(
                      child: Image.network(
                        payload.webRemoteUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => _ImageFallback(
                          fallbackText: _initial(widget.produto.descricao),
                        ),
                      ),
                    );
                  }

                  return _ImageFallback(
                    fallbackText: _initial(widget.produto.descricao),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductImagePreviewResolver {
  const ProductImagePreviewResolver._();

  static Future<ProductImagePreviewPayload> resolve(Produto produto) async {
    final thumbnailBytes = _decodeBase64(produto.thumbnailBase64);
    final photoUrl = (produto.fotoUrl ?? '').trim();
    final storagePath = (produto.storagePath ?? '').trim();

    if (!kIsWeb) {
      final localFullBytes = await MobileProductImageCacheService.instance
          .readFullBytes(produto: produto);
      if (localFullBytes != null && localFullBytes.isNotEmpty) {
        return ProductImagePreviewPayload(
          bytes: localFullBytes,
          webRemoteUrl: '',
        );
      }

      final localThumbBytes = await MobileProductImageCacheService.instance
          .readThumbnailBytes(produto: produto);
      if (localThumbBytes != null && localThumbBytes.isNotEmpty) {
        return ProductImagePreviewPayload(
          bytes: localThumbBytes,
          webRemoteUrl: '',
        );
      }

      return ProductImagePreviewPayload(
        bytes: thumbnailBytes,
        webRemoteUrl: '',
      );
    }

    final webUrl = await _resolveRemoteUrl(
      photoUrl: photoUrl,
      storagePath: storagePath,
    );
    return ProductImagePreviewPayload(
      bytes: thumbnailBytes,
      webRemoteUrl: webUrl,
    );
  }

  static Future<String> _resolveRemoteUrl({
    required String photoUrl,
    required String storagePath,
  }) async {
    if (_isHttp(photoUrl)) {
      return photoUrl;
    }

    if (storagePath.isNotEmpty) {
      try {
        return await FirebaseStorage.instance
            .ref(storagePath)
            .getDownloadURL()
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        // Fallback to other source candidates.
      }
    }

    if (_looksLikeStoragePath(photoUrl)) {
      try {
        return await FirebaseStorage.instance
            .ref(photoUrl)
            .getDownloadURL()
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        // No valid remote URL available.
      }
    }

    return '';
  }

  static Uint8List? _decodeBase64(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }

    try {
      final bytes = base64Decode(normalized);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  static bool _isHttp(String value) {
    final normalized = value.toLowerCase();
    return normalized.startsWith('http://') ||
        normalized.startsWith('https://');
  }

  static bool _looksLikeStoragePath(String value) {
    final normalized = value.toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.startsWith('http://') ||
        normalized.startsWith('https://') ||
        normalized.startsWith('gs://')) {
      return false;
    }
    return normalized.startsWith('tenants/') ||
        normalized.contains('/product_media/');
  }
}

class ProductImagePreviewPayload {
  const ProductImagePreviewPayload({
    required this.bytes,
    required this.webRemoteUrl,
  });

  final Uint8List? bytes;
  final String webRemoteUrl;
}

class _ZoomableImage extends StatelessWidget {
  const _ZoomableImage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.7,
      maxScale: 4.0,
      child: Center(child: child),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.fallbackText});

  final String fallbackText;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          fallbackText,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}

String _initial(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return '?';
  }
  return normalized[0].toUpperCase();
}
