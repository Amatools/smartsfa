import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

class ProductMediaUploadResult {
  const ProductMediaUploadResult({
    required this.assetId,
    required this.tenantId,
    required this.representedCompanyId,
    required this.scopeKey,
    required this.fileName,
    required this.downloadUrl,
    required this.storagePath,
    required this.thumbnailBase64,
    required this.previewBytes,
    required this.width,
    required this.height,
    required this.createdAt,
    required this.updatedAt,
  });

  final String assetId;
  final String tenantId;
  final String? representedCompanyId;
  final String scopeKey;
  final String fileName;
  final String downloadUrl;
  final String storagePath;
  final String thumbnailBase64;
  final Uint8List previewBytes;
  final int width;
  final int height;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ProductMediaUploadService {
  const ProductMediaUploadService();

  Future<ProductMediaUploadResult?> pickAndUpload({
    required String tenantId,
    required String scopeKey,
    String? representedCompanyId,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (picked == null || picked.files.isEmpty) {
      return null;
    }

    final selectedFile = picked.files.first;
    final bytes = selectedFile.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Nao foi possivel ler a imagem selecionada.');
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Formato de imagem invalido.');
    }

    final processed = _resizeAndCropToSquare(decoded, 500);
    final jpgBytes = Uint8List.fromList(img.encodeJpg(processed, quality: 88));
    final thumbBase64 = _buildThumbnailBase64(processed);
    final now = DateTime.now().toUtc();
    final assetId = 'pma_${now.microsecondsSinceEpoch}';
    final normalizedFileName = selectedFile.name.trim().isEmpty
        ? '$assetId.jpg'
        : selectedFile.name.trim();
    final normalizedRepresentedCompanyId = (representedCompanyId ?? '').trim().isEmpty
        ? null
        : representedCompanyId!.trim();

    final storagePath = 'tenants/$tenantId/product_media/$scopeKey/$assetId.jpg';
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(
      jpgBytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'origin': 'product-media-library',
          'scope-key': scopeKey,
          'max-size': '500x500-square',
          'encoded-as': 'jpg-q88',
        },
      ),
    ).timeout(const Duration(seconds: 45));

    final downloadUrl = await ref.getDownloadURL().timeout(const Duration(seconds: 20));

    await FirebaseFirestore.instance.collection('product_media_assets').doc(assetId).set(
      {
        'tenantId': tenantId,
        'representedCompanyId': normalizedRepresentedCompanyId,
        'scopeKey': scopeKey,
        'fileName': normalizedFileName,
        'downloadUrl': downloadUrl,
        'storagePath': storagePath,
        'thumbnailBase64': thumbBase64,
        'width': 500,
        'height': 500,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      },
    );

    return ProductMediaUploadResult(
      assetId: assetId,
      tenantId: tenantId,
      representedCompanyId: normalizedRepresentedCompanyId,
      scopeKey: scopeKey,
      fileName: normalizedFileName,
      downloadUrl: downloadUrl,
      storagePath: storagePath,
      thumbnailBase64: thumbBase64,
      previewBytes: jpgBytes,
      width: 500,
      height: 500,
      createdAt: now,
      updatedAt: now,
    );
  }

  img.Image _resizeAndCropToSquare(img.Image source, int size) {
    final width = source.width;
    final height = source.height;
    final squareSize = width < height ? width : height;
    final offsetX = ((width - squareSize) / 2).round();
    final offsetY = ((height - squareSize) / 2).round();
    final squared = img.copyCrop(
      source,
      x: offsetX < 0 ? 0 : offsetX,
      y: offsetY < 0 ? 0 : offsetY,
      width: squareSize,
      height: squareSize,
    );
    if (squared.width == size && squared.height == size) {
      return squared;
    }
    return img.copyResize(
      squared,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
  }

  String _buildThumbnailBase64(img.Image source) {
    final thumb = img.copyResize(
      source,
      width: 96,
      height: 96,
      interpolation: img.Interpolation.average,
    );
    final bytes = img.encodeJpg(thumb, quality: 70);
    return base64Encode(bytes);
  }
}