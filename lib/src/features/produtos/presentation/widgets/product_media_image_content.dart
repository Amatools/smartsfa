import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../services/product_media_path_utils.dart';

class ProductMediaImageContent extends StatelessWidget {
  const ProductMediaImageContent({
    super.key,
    required this.photoUrl,
    this.storagePath,
    required this.previewBytes,
    required this.size,
    required this.fallbackText,
  });

  final String photoUrl;
  final String? storagePath;
  final Uint8List? previewBytes;
  final double size;
  final String fallbackText;

  @override
  Widget build(BuildContext context) {
    final preview = previewBytes;
    final normalizedPhotoUrl = photoUrl.trim();
    final providedStoragePath = (storagePath ?? '').trim();
    final normalizedStoragePath = providedStoragePath.isNotEmpty
        ? providedStoragePath
        : (ProductMediaPathUtils.looksLikeStorageObjectPath(normalizedPhotoUrl)
            ? normalizedPhotoUrl
            : '');
    if (preview != null && preview.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.memory(preview, fit: BoxFit.cover),
      );
    }

    final hasDirectUrl = normalizedPhotoUrl.isNotEmpty &&
        (ProductMediaPathUtils.isHttpImageUrl(normalizedPhotoUrl) ||
            ProductMediaPathUtils.isFirebaseStorageUrl(normalizedPhotoUrl));
    if (hasDirectUrl) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.network(
          normalizedPhotoUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            if (normalizedStoragePath.isNotEmpty) {
              return _FirebaseStorageImage(
                photoUrl: normalizedPhotoUrl,
                storagePath: normalizedStoragePath,
                size: size,
                fallbackText: fallbackText,
              );
            }
            return _MediaImageFallback(fallbackText: fallbackText);
          },
        ),
      );
    }

    if (normalizedStoragePath.isNotEmpty ||
        ProductMediaPathUtils.isFirebaseStorageUrl(normalizedPhotoUrl)) {
      return _FirebaseStorageImage(
        photoUrl: normalizedPhotoUrl,
        storagePath: normalizedStoragePath,
        size: size,
        fallbackText: fallbackText,
      );
    }

    return _MediaImageFallback(fallbackText: fallbackText);
  }
}

class _FirebaseStorageImage extends StatefulWidget {
  const _FirebaseStorageImage({
    required this.photoUrl,
    this.storagePath,
    required this.size,
    required this.fallbackText,
  });

  final String photoUrl;
  final String? storagePath;
  final double size;
  final String fallbackText;

  @override
  State<_FirebaseStorageImage> createState() => _FirebaseStorageImageState();
}

class _FirebaseStorageImageState extends State<_FirebaseStorageImage> {
  late Future<List<String>> _candidateUrlsFuture;

  @override
  void initState() {
    super.initState();
    _candidateUrlsFuture = _resolveCandidateUrls(
      widget.photoUrl,
      storagePath: widget.storagePath,
    );
  }

  @override
  void didUpdateWidget(covariant _FirebaseStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl || oldWidget.storagePath != widget.storagePath) {
      _candidateUrlsFuture = _resolveCandidateUrls(
        widget.photoUrl,
        storagePath: widget.storagePath,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _candidateUrlsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final urls = snapshot.data ?? const <String>[];
        if (urls.isEmpty) {
          return _MediaImageFallback(fallbackText: widget.fallbackText);
        }

        return _NetworkFallbackImage(
          urls: urls,
          fallbackText: widget.fallbackText,
        );
      },
    );
  }

  Future<List<String>> _resolveCandidateUrls(String photoUrl, {String? storagePath}) async {
    final urls = <String>[];
    void addUrl(String value) {
      final normalized = value.trim();
      if (normalized.isEmpty) {
        return;
      }
      if (!urls.contains(normalized)) {
        urls.add(normalized);
      }
    }

    if (ProductMediaPathUtils.isHttpImageUrl(photoUrl) ||
        ProductMediaPathUtils.isFirebaseStorageUrl(photoUrl)) {
      addUrl(photoUrl);
    }

    final normalizedPath = (storagePath ?? '').trim();
    if (normalizedPath.isNotEmpty) {
      try {
        final byPath = await FirebaseStorage.instance
            .ref(normalizedPath)
            .getDownloadURL()
            .timeout(const Duration(seconds: 20));
        addUrl(byPath);
      } catch (_) {
        // Keep trying other loading strategies.
      }
    }

    try {
      final ref = _storageRefFromUrl(photoUrl);
      if (ref != null) {
        final byRef = await ref.getDownloadURL().timeout(const Duration(seconds: 20));
        addUrl(byRef);
      }
    } catch (_) {
      // Continue with Firestore media metadata fallback.
    }

    final fromMediaAsset = await _loadMediaAssetUrl(photoUrl);
    if (fromMediaAsset != null && fromMediaAsset.isNotEmpty) {
      addUrl(fromMediaAsset);
    }

    return urls;
  }

  Future<String?> _loadMediaAssetUrl(String photoUrl) async {
    final normalized = photoUrl.trim();
    if (normalized.isEmpty) {
      return null;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('product_media_assets')
          .where('downloadUrl', isEqualTo: normalized)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final storagePath = (snapshot.docs.first.data()['storagePath'] as String? ?? '').trim();
        if (storagePath.isNotEmpty) {
          return await FirebaseStorage.instance
              .ref(storagePath)
              .getDownloadURL()
              .timeout(const Duration(seconds: 20));
        }
      }

      final byPath = await FirebaseFirestore.instance
          .collection('product_media_assets')
          .where('storagePath', isEqualTo: normalized)
          .limit(1)
          .get();
      if (byPath.docs.isEmpty) {
        return null;
      }
      final storagePath = (byPath.docs.first.data()['storagePath'] as String? ?? '').trim();
      if (storagePath.isEmpty) {
        return null;
      }

      return await FirebaseStorage.instance
          .ref(storagePath)
          .getDownloadURL()
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      return null;
    }
  }

  Reference? _storageRefFromUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return null;
    }

    if (raw.startsWith('gs://')) {
      return FirebaseStorage.instance.refFromURL(raw);
    }

    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return null;
    }

    final objectIndex = uri.path.indexOf('/o/');
    if (objectIndex >= 0) {
      final encodedPath = uri.path.substring(objectIndex + 3);
      final decodedPath = Uri.decodeComponent(encodedPath).trim();
      if (decodedPath.isNotEmpty) {
        return FirebaseStorage.instance.ref(decodedPath);
      }
    }

    try {
      return FirebaseStorage.instance.refFromURL(raw);
    } catch (_) {
      return null;
    }
  }
}

class _NetworkFallbackImage extends StatefulWidget {
  const _NetworkFallbackImage({required this.urls, required this.fallbackText});

  final List<String> urls;
  final String fallbackText;

  @override
  State<_NetworkFallbackImage> createState() => _NetworkFallbackImageState();
}

class _NetworkFallbackImageState extends State<_NetworkFallbackImage> {
  int _activeIndex = 0;

  @override
  void didUpdateWidget(covariant _NetworkFallbackImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') != widget.urls.join('|')) {
      _activeIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty || _activeIndex >= widget.urls.length) {
      return _MediaImageFallback(fallbackText: widget.fallbackText);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.network(
        widget.urls[_activeIndex],
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          if (_activeIndex < widget.urls.length - 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              setState(() {
                _activeIndex += 1;
              });
            });
            return const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          return _MediaImageFallback(fallbackText: widget.fallbackText);
        },
      ),
    );
  }
}

class _MediaImageFallback extends StatelessWidget {
  const _MediaImageFallback({required this.fallbackText});

  final String fallbackText;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 28,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
