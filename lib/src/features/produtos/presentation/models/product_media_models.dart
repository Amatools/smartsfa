import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

class ProductMediaAsset {
  const ProductMediaAsset({
    required this.id,
    required this.tenantId,
    required this.representedCompanyId,
    required this.scopeKey,
    required this.fileName,
    required this.downloadUrl,
    required this.storagePath,
    this.thumbnailBase64,
    required this.width,
    required this.height,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductMediaAsset.fromMap(String id, Map<String, Object?> map) {
    final rawDownloadUrl = ((map['downloadUrl'] as String?) ?? '').trim();
    final rawFotoUrl = ((map['fotoUrl'] as String?) ?? '').trim();
    final rawUrl = ((map['url'] as String?) ?? '').trim();
    final rawStoragePath = ((map['storagePath'] as String?) ??
            (map['path'] as String?) ??
            (map['objectPath'] as String?) ??
            '')
        .trim();
    final normalizedDownloadUrl = [rawDownloadUrl, rawFotoUrl, rawUrl]
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final fileNameValue = (map['fileName'] as String? ?? id).trim();
    final decodedThumbnailBase64 = (map['thumbnailBase64'] as String?)?.trim();
    final thumbBase64Alt = (map['thumbBase64'] as String?)?.trim();

    return ProductMediaAsset(
      id: id,
      tenantId: map['tenantId'] as String? ?? '',
      representedCompanyId: map['representedCompanyId'] as String?,
      scopeKey: map['scopeKey'] as String? ?? 'tenant_default',
      fileName: fileNameValue.isEmpty ? id : fileNameValue,
      downloadUrl: normalizedDownloadUrl,
      storagePath: rawStoragePath,
      thumbnailBase64: decodedThumbnailBase64 != null && decodedThumbnailBase64.isNotEmpty
          ? decodedThumbnailBase64
          : (thumbBase64Alt != null && thumbBase64Alt.isNotEmpty ? thumbBase64Alt : null),
      width: (map['width'] as num?)?.toInt() ?? 500,
      height: (map['height'] as num?)?.toInt() ?? 500,
      createdAt: _readMediaDateTime(map['createdAt']),
      updatedAt: _readMediaDateTime(map['updatedAt']),
    );
  }

  final String id;
  final String tenantId;
  final String? representedCompanyId;
  final String scopeKey;
  final String fileName;
  final String downloadUrl;
  final String storagePath;
  final String? thumbnailBase64;
  final int width;
  final int height;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return {
      'tenantId': tenantId,
      'representedCompanyId': representedCompanyId,
      'scopeKey': scopeKey,
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'storagePath': storagePath,
      'thumbnailBase64': thumbnailBase64,
      'width': width,
      'height': height,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}

class ProductMediaSelection {
  const ProductMediaSelection({
    this.asset,
    this.previewBytes,
    this.withoutImage = false,
  });

  final ProductMediaAsset? asset;
  final Uint8List? previewBytes;
  final bool withoutImage;
}

Uint8List? decodeBase64Image(String? value) {
  final normalized = (value ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }

  try {
    final bytes = base64Decode(normalized);
    if (bytes.isEmpty) {
      return null;
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

DateTime _readMediaDateTime(Object? value) {
  if (value is Timestamp) {
    return value.toDate().toUtc();
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
