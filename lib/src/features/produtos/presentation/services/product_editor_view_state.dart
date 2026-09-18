import 'dart:typed_data';

import '../../../../core/models/domain_types.dart';

class ProductEditorViewState {
  const ProductEditorViewState({
    required this.status,
    required this.bitolaUnit,
    required this.currencyCode,
    required this.saving,
    required this.loadingTablePrice,
    required this.uploadingImage,
    required this.imageExplicitlyCleared,
    required this.currentImagePreviewBytes,
    required this.currentImageStoragePath,
    required this.currentImageThumbBase64,
  });

  factory ProductEditorViewState.initial({
    required ProductStatus status,
    required String bitolaUnit,
    required String currencyCode,
    required String? currentImageStoragePath,
    required String? currentImageThumbBase64,
  }) {
    return ProductEditorViewState(
      status: status,
      bitolaUnit: bitolaUnit,
      currencyCode: currencyCode,
      saving: false,
      loadingTablePrice: false,
      uploadingImage: false,
      imageExplicitlyCleared: false,
      currentImagePreviewBytes: null,
      currentImageStoragePath: currentImageStoragePath,
      currentImageThumbBase64: currentImageThumbBase64,
    );
  }

  final ProductStatus status;
  final String bitolaUnit;
  final String currencyCode;
  final bool saving;
  final bool loadingTablePrice;
  final bool uploadingImage;
  final bool imageExplicitlyCleared;
  final Uint8List? currentImagePreviewBytes;
  final String? currentImageStoragePath;
  final String? currentImageThumbBase64;

  static const Object _noValue = Object();

  ProductEditorViewState copyWith({
    ProductStatus? status,
    String? bitolaUnit,
    String? currencyCode,
    bool? saving,
    bool? loadingTablePrice,
    bool? uploadingImage,
    bool? imageExplicitlyCleared,
    Object? currentImagePreviewBytes = _noValue,
    Object? currentImageStoragePath = _noValue,
    Object? currentImageThumbBase64 = _noValue,
  }) {
    return ProductEditorViewState(
      status: status ?? this.status,
      bitolaUnit: bitolaUnit ?? this.bitolaUnit,
      currencyCode: currencyCode ?? this.currencyCode,
      saving: saving ?? this.saving,
      loadingTablePrice: loadingTablePrice ?? this.loadingTablePrice,
      uploadingImage: uploadingImage ?? this.uploadingImage,
      imageExplicitlyCleared:
          imageExplicitlyCleared ?? this.imageExplicitlyCleared,
      currentImagePreviewBytes: identical(currentImagePreviewBytes, _noValue)
          ? this.currentImagePreviewBytes
          : currentImagePreviewBytes as Uint8List?,
      currentImageStoragePath: identical(currentImageStoragePath, _noValue)
          ? this.currentImageStoragePath
          : currentImageStoragePath as String?,
      currentImageThumbBase64: identical(currentImageThumbBase64, _noValue)
          ? this.currentImageThumbBase64
          : currentImageThumbBase64 as String?,
    );
  }

  ProductEditorViewState withStatus(ProductStatus value) {
    return copyWith(status: value);
  }

  ProductEditorViewState withBitolaUnit(String value) {
    return copyWith(bitolaUnit: value);
  }

  ProductEditorViewState withCurrencyCode(String value) {
    return copyWith(currencyCode: value);
  }

  ProductEditorViewState withSaving(bool value) {
    return copyWith(saving: value);
  }

  ProductEditorViewState withLoadingTablePrice(bool value) {
    return copyWith(loadingTablePrice: value);
  }

  ProductEditorViewState withUploadingImage(bool value) {
    return copyWith(uploadingImage: value);
  }

  ProductEditorViewState withMediaState({
    required bool imageExplicitlyCleared,
    required Uint8List? currentImagePreviewBytes,
    required String? currentImageStoragePath,
    required String? currentImageThumbBase64,
  }) {
    return copyWith(
      imageExplicitlyCleared: imageExplicitlyCleared,
      currentImagePreviewBytes: currentImagePreviewBytes,
      currentImageStoragePath: currentImageStoragePath,
      currentImageThumbBase64: currentImageThumbBase64,
    );
  }

  ProductEditorViewState withPostSaveReset({
    required ProductStatus status,
    required String bitolaUnit,
    required String currencyCode,
  }) {
    return copyWith(
      status: status,
      bitolaUnit: bitolaUnit,
      currencyCode: currencyCode,
    );
  }
}
