import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/produto.dart';
import '../../../../core/services/mobile_product_image_cache_service.dart';
import '../models/product_media_models.dart';
import 'product_media_image_content.dart';

class ProductThumbnail extends StatefulWidget {
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
  State<ProductThumbnail> createState() => _ProductThumbnailState();
}

class _ProductThumbnailState extends State<ProductThumbnail> {
  Uint8List? _localThumbBytes;

  @override
  void initState() {
    super.initState();
    _loadLocalThumbnail();
  }

  @override
  void didUpdateWidget(covariant ProductThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.produto.id != widget.produto.id ||
        oldWidget.produto.syncVersion != widget.produto.syncVersion ||
        oldWidget.produto.fotoUrl != widget.produto.fotoUrl ||
        oldWidget.produto.storagePath != widget.produto.storagePath ||
        oldWidget.produto.thumbnailBase64 != widget.produto.thumbnailBase64) {
      _loadLocalThumbnail();
    }
  }

  Future<void> _loadLocalThumbnail() async {
    if (kIsWeb) {
      return;
    }

    final bytes = await MobileProductImageCacheService.instance
        .readThumbnailBytes(produto: widget.produto);
    if (!mounted) {
      return;
    }
    setState(() {
      _localThumbBytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.produto.fotoUrl?.trim();
    final persistedStoragePath = (widget.produto.storagePath ?? '').trim();
    final persistedThumbBytes = decodeBase64Image(
      widget.produto.thumbnailBase64,
    );
    final incomingStoragePath = (widget.storagePath ?? '').trim();
    final resolvedStoragePath = persistedStoragePath.isNotEmpty
        ? persistedStoragePath
        : incomingStoragePath;
    final resolvedPreviewBytes =
        widget.previewBytes ?? _localThumbBytes ?? persistedThumbBytes;
    final hasAnyImageSource =
        (resolvedPreviewBytes != null && resolvedPreviewBytes.isNotEmpty) ||
        ((photoUrl != null && photoUrl.isNotEmpty) ||
            resolvedStoragePath.isNotEmpty);
    final initials = widget.produto.descricao.isNotEmpty
        ? widget.produto.descricao[0].toUpperCase()
        : '?';

    final content = Container(
      width: widget.size,
      height: widget.size,
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
      child: widget.uploading
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
                widget.onTap == null
                    ? Icons.image_outlined
                    : Icons.add_photo_alternate_outlined,
                size: widget.size <= 60 ? 24 : 30,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : ProductMediaImageContent(
              photoUrl: photoUrl ?? '',
              storagePath: resolvedStoragePath,
              previewBytes: resolvedPreviewBytes,
              size: widget.size,
              fallbackText: initials,
            ),
    );

    if (widget.onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: content,
      ),
    );
  }
}
