import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProductMediaLibraryService {
  const ProductMediaLibraryService();

  Future<bool> isAssetInUse({
    required String tenantId,
    required String downloadUrl,
    required String storagePath,
  }) async {
    final checks = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    final normalizedDownloadUrl = downloadUrl.trim();
    final normalizedStoragePath = storagePath.trim();

    if (normalizedDownloadUrl.isNotEmpty) {
      checks.add(
        FirebaseFirestore.instance
            .collection('produtos')
            .where('tenantId', isEqualTo: tenantId)
            .where('fotoUrl', isEqualTo: normalizedDownloadUrl)
            .limit(1)
            .get(),
      );
    }

    if (normalizedStoragePath.isNotEmpty) {
      checks.add(
        FirebaseFirestore.instance
            .collection('produtos')
            .where('tenantId', isEqualTo: tenantId)
            .where('fotoUrl', isEqualTo: normalizedStoragePath)
            .limit(1)
            .get(),
      );
      checks.add(
        FirebaseFirestore.instance
            .collection('produtos')
            .where('tenantId', isEqualTo: tenantId)
            .where('storagePath', isEqualTo: normalizedStoragePath)
            .limit(1)
            .get(),
      );
    }

    if (checks.isEmpty) {
      return false;
    }

    final snapshots = await Future.wait(checks);
    for (final snapshot in snapshots) {
      if (snapshot.docs.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<void> deleteAsset({
    required String assetId,
    required String storagePath,
  }) async {
    final normalizedStoragePath = storagePath.trim();
    if (normalizedStoragePath.isNotEmpty) {
      await FirebaseStorage.instance.ref(normalizedStoragePath).delete();
    }

    await FirebaseFirestore.instance.collection('product_media_assets').doc(assetId).delete();
  }
}