import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/produto.dart';

class MobileProductImageCacheService {
  MobileProductImageCacheService._();

  static final MobileProductImageCacheService instance =
      MobileProductImageCacheService._();

  static const String _prefsKey = 'smart_sfa_mobile_product_image_cache_v1';
  final Map<String, _MobileImageCacheEntry> _entries =
      <String, _MobileImageCacheEntry>{};
  final Map<String, Uint8List> _thumbMemory = <String, Uint8List>{};
  final Map<String, Uint8List> _fullMemory = <String, Uint8List>{};
  bool _indexLoaded = false;

  Future<void> syncProductsFromPayloads({
    required String tenantId,
    required Iterable<Map<String, Object?>> payloads,
  }) async {
    if (kIsWeb) {
      return;
    }

    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return;
    }

    await _ensureIndexLoaded();
    final cacheDir = await _resolveTenantCacheDirectory(normalizedTenantId);
    var indexChanged = false;

    for (final payload in payloads) {
      final productId = _readString(payload['id']);
      if (productId.isEmpty) {
        continue;
      }

      final photoUrl = _readString(payload['fotoUrl']);
      final storagePath = _readString(payload['storagePath']);
      final thumbBase64 = _readString(payload['thumbnailBase64']);
      final syncVersion = _readInt(payload['syncVersion']) ?? 0;
      final signature = _buildSignature(
        syncVersion: syncVersion,
        photoUrl: photoUrl,
        storagePath: storagePath,
        thumbnailBase64: thumbBase64,
      );
      final cacheKey = _composeCacheKey(normalizedTenantId, productId);
      final existing = _entries[cacheKey];

      if (existing != null && existing.signature == signature) {
        final hasFull = await _hasFile(existing.fullPath);
        final hasThumb = await _hasFile(existing.thumbPath);
        if (hasFull || hasThumb) {
          continue;
        }
      }

      Uint8List? thumbnailBytes = _decodeBase64(thumbBase64);
      Uint8List? fullBytes;

      final remoteUrl = await _resolveRemoteUrl(
        photoUrl: photoUrl,
        storagePath: storagePath,
      );
      if (remoteUrl.isNotEmpty) {
        fullBytes = await _downloadImageBytes(remoteUrl);
      }

      if (thumbnailBytes == null && fullBytes != null) {
        thumbnailBytes = _buildThumbnailBytes(fullBytes);
      }

      if (fullBytes == null && thumbnailBytes == null) {
        if (existing != null) {
          await _deleteEntryFiles(existing);
          _entries.remove(cacheKey);
          _thumbMemory.remove(cacheKey);
          _fullMemory.remove(cacheKey);
          indexChanged = true;
        }
        continue;
      }

      final fileStem =
          '${_sanitizeFilePart(productId)}_${_fingerprint(signature)}';
      String? fullPath;
      String? thumbPath;

      if (fullBytes != null) {
        final file = File(
          '${cacheDir.path}${Platform.pathSeparator}${fileStem}_full.bin',
        );
        await file.writeAsBytes(fullBytes, flush: true);
        fullPath = file.path;
        _fullMemory[cacheKey] = fullBytes;
      }

      if (thumbnailBytes != null) {
        final file = File(
          '${cacheDir.path}${Platform.pathSeparator}${fileStem}_thumb.jpg',
        );
        await file.writeAsBytes(thumbnailBytes, flush: true);
        thumbPath = file.path;
        _thumbMemory[cacheKey] = thumbnailBytes;
      }

      await _deleteEntryFiles(
        existing,
        preservePaths: <String>{
          if (fullPath != null && fullPath.isNotEmpty) fullPath,
          if (thumbPath != null && thumbPath.isNotEmpty) thumbPath,
        },
      );

      _entries[cacheKey] = _MobileImageCacheEntry(
        signature: signature,
        fullPath: fullPath ?? '',
        thumbPath: thumbPath ?? '',
        updatedAtIso: DateTime.now().toUtc().toIso8601String(),
      );
      indexChanged = true;
    }

    if (indexChanged) {
      await _persistIndex();
    }
  }

  Future<Uint8List?> readThumbnailBytes({required Produto produto}) async {
    if (kIsWeb) {
      return _decodeBase64(produto.thumbnailBase64);
    }

    await _ensureIndexLoaded();
    final cacheKey = _composeCacheKey(produto.tenantId, produto.id);
    final expectedSignature = _signatureForProduct(produto);
    final entry = _entries[cacheKey];
    if (entry == null || entry.signature != expectedSignature) {
      return _decodeBase64(produto.thumbnailBase64);
    }

    final inMemory = _thumbMemory[cacheKey];
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }

    final fromFile = await _readFileBytes(entry.thumbPath);
    if (fromFile != null && fromFile.isNotEmpty) {
      _thumbMemory[cacheKey] = fromFile;
      return fromFile;
    }

    final fullBytes = await readFullBytes(produto: produto);
    if (fullBytes != null && fullBytes.isNotEmpty) {
      final generatedThumb = _buildThumbnailBytes(fullBytes);
      if (generatedThumb != null && generatedThumb.isNotEmpty) {
        _thumbMemory[cacheKey] = generatedThumb;
        return generatedThumb;
      }
    }

    return _decodeBase64(produto.thumbnailBase64);
  }

  Future<Uint8List?> readFullBytes({required Produto produto}) async {
    if (kIsWeb) {
      return null;
    }

    await _ensureIndexLoaded();
    final cacheKey = _composeCacheKey(produto.tenantId, produto.id);
    final expectedSignature = _signatureForProduct(produto);
    final entry = _entries[cacheKey];
    if (entry == null || entry.signature != expectedSignature) {
      return null;
    }

    final inMemory = _fullMemory[cacheKey];
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }

    final fromFile = await _readFileBytes(entry.fullPath);
    if (fromFile == null || fromFile.isEmpty) {
      return null;
    }

    _fullMemory[cacheKey] = fromFile;
    return fromFile;
  }

  Future<void> _ensureIndexLoaded() async {
    if (_indexLoaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              _entries[key] = _MobileImageCacheEntry.fromMap(value);
            } else if (value is Map) {
              _entries[key] = _MobileImageCacheEntry.fromMap(
                Map<String, dynamic>.from(value),
              );
            }
          });
        }
      } catch (_) {
        // Ignore corrupted cache index and rebuild on next sync.
      }
    }

    _indexLoaded = true;
  }

  Future<void> _persistIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = <String, Object?>{};
    _entries.forEach((key, value) {
      serialized[key] = value.toMap();
    });
    await prefs.setString(_prefsKey, jsonEncode(serialized));
  }

  Future<Directory> _resolveTenantCacheDirectory(String tenantId) async {
    final baseDir = await getApplicationSupportDirectory();
    final safeTenantId = _sanitizeFilePart(tenantId);
    final path =
        '${baseDir.path}${Platform.pathSeparator}product_image_cache${Platform.pathSeparator}$safeTenantId';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _deleteEntryFiles(
    _MobileImageCacheEntry? entry, {
    Set<String>? preservePaths,
  }) async {
    if (entry == null) {
      return;
    }

    final preserved = preservePaths ?? const <String>{};
    for (final path in <String>[entry.fullPath, entry.thumbPath]) {
      final normalized = path.trim();
      if (normalized.isEmpty || preserved.contains(normalized)) {
        continue;
      }

      final file = File(normalized);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<bool> _hasFile(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final file = File(normalized);
    return file.exists();
  }

  Future<Uint8List?> _readFileBytes(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final file = File(normalized);
    if (!await file.exists()) {
      return null;
    }

    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<String> _resolveRemoteUrl({
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
            .timeout(const Duration(seconds: 25));
      } catch (_) {
        // Keep trying other path candidates.
      }
    }

    if (_looksLikeStoragePath(photoUrl)) {
      try {
        return await FirebaseStorage.instance
            .ref(photoUrl)
            .getDownloadURL()
            .timeout(const Duration(seconds: 25));
      } catch (_) {
        // No valid remote URL available.
      }
    }

    return '';
  }

  Future<Uint8List?> _downloadImageBytes(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 35));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      if (response.bodyBytes.isEmpty) {
        return null;
      }
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Uint8List? _buildThumbnailBytes(Uint8List sourceBytes) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      return null;
    }

    final thumbnail = img.copyResize(
      decoded,
      width: 96,
      height: 96,
      interpolation: img.Interpolation.average,
    );
    final bytes = img.encodeJpg(thumbnail, quality: 72);
    if (bytes.isEmpty) {
      return null;
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List? _decodeBase64(String? value) {
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

  String _signatureForProduct(Produto produto) {
    return _buildSignature(
      syncVersion: produto.syncVersion,
      photoUrl: (produto.fotoUrl ?? '').trim(),
      storagePath: (produto.storagePath ?? '').trim(),
      thumbnailBase64: (produto.thumbnailBase64 ?? '').trim(),
    );
  }

  String _buildSignature({
    required int syncVersion,
    required String photoUrl,
    required String storagePath,
    required String thumbnailBase64,
  }) {
    return '$syncVersion|$photoUrl|$storagePath|${thumbnailBase64.length}';
  }

  String _composeCacheKey(String tenantId, String productId) {
    return '${tenantId.trim()}::${productId.trim()}';
  }

  String _sanitizeFilePart(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'unknown';
    }
    return normalized.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  String _fingerprint(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  bool _isHttp(String value) {
    final normalized = value.toLowerCase();
    return normalized.startsWith('http://') ||
        normalized.startsWith('https://');
  }

  bool _looksLikeStoragePath(String value) {
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

  String _readString(Object? value) {
    return value?.toString().trim() ?? '';
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString().trim() ?? '');
  }
}

class _MobileImageCacheEntry {
  const _MobileImageCacheEntry({
    required this.signature,
    required this.fullPath,
    required this.thumbPath,
    required this.updatedAtIso,
  });

  factory _MobileImageCacheEntry.fromMap(Map<String, dynamic> map) {
    return _MobileImageCacheEntry(
      signature: (map['signature'] ?? '').toString(),
      fullPath: (map['fullPath'] ?? '').toString(),
      thumbPath: (map['thumbPath'] ?? '').toString(),
      updatedAtIso: (map['updatedAtIso'] ?? '').toString(),
    );
  }

  final String signature;
  final String fullPath;
  final String thumbPath;
  final String updatedAtIso;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'signature': signature,
      'fullPath': fullPath,
      'thumbPath': thumbPath,
      'updatedAtIso': updatedAtIso,
    };
  }
}
