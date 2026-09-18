import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';
import '../models/product_media_models.dart';
import 'product_media_image_content.dart';

class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    required this.produto,
    this.size = 84,
    this.uploading = false,
    this.storagePath,
    this.previewBytes,
    this.onTap,
  });

  final Produto produto;
  final double size;
  final bool uploading;
  final String? storagePath;
  final Uint8List? previewBytes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final photoUrl = produto.fotoUrl?.trim();
    final persistedStoragePath = (produto.storagePath ?? '').trim();
    final persistedThumbBytes = decodeBase64Image(produto.thumbnailBase64);
    final incomingStoragePath = (storagePath ?? '').trim();
    final resolvedStoragePath =
        persistedStoragePath.isNotEmpty ? persistedStoragePath : incomingStoragePath;
    final hasAnyImageSource =
        (photoUrl != null && photoUrl.isNotEmpty) || resolvedStoragePath.isNotEmpty;
    final initials = produto.descricao.isNotEmpty ? produto.descricao[0].toUpperCase() : '?';

    final content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: uploading
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : !hasAnyImageSource
              ? Center(
                  child: Icon(
                    onTap == null ? Icons.image_outlined : Icons.add_photo_alternate_outlined,
                    size: size <= 60 ? 24 : 30,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              : ProductMediaImageContent(
                  photoUrl: photoUrl ?? '',
                  storagePath: resolvedStoragePath,
                  previewBytes: previewBytes ?? persistedThumbBytes,
                  size: size,
                  fallbackText: initials,
                ),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: content,
      ),
    );
  }
}