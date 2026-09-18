class ProductMediaPathUtils {
  const ProductMediaPathUtils._();

  static bool isFirebaseStorageUrl(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('gs://') ||
        normalized.contains('firebasestorage.googleapis.com') ||
        normalized.contains('.firebasestorage.app');
  }

  static bool isHttpImageUrl(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('https://') || normalized.startsWith('http://');
  }

  static bool looksLikeStorageObjectPath(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final hasScheme = normalized.startsWith('http://') ||
        normalized.startsWith('https://') ||
        normalized.startsWith('gs://');
    if (hasScheme) {
      return false;
    }
    return normalized.startsWith('tenants/') || normalized.contains('/product_media/');
  }
}