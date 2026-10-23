import 'package:cloud_firestore/cloud_firestore.dart';

class ProductTaxGroupCatalogEntry {
  const ProductTaxGroupCatalogEntry({
    required this.id,
    required this.name,
    this.description,
    this.status,
  });

  final String id;
  final String name;
  final String? description;
  final String? status;

  String get displayLabel {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) {
      return trimmedName;
    }
    return id;
  }

  bool get isActive {
    final normalizedStatus = (status ?? '').trim().toLowerCase();
    if (normalizedStatus.isEmpty) {
      return true;
    }
    return normalizedStatus == 'active' ||
        normalizedStatus == 'ativo' ||
        normalizedStatus == 'enabled';
  }
}

class ProductTaxGroupCatalogService {
  ProductTaxGroupCatalogService(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('tax_rule_groups');

  Stream<List<ProductTaxGroupCatalogEntry>> watchGroups({
    required String tenantId,
  }) {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      return Stream.value(const <ProductTaxGroupCatalogEntry>[]);
    }

    return _collection
        .where('tenantId', isEqualTo: normalizedTenantId)
        .snapshots()
        .map((snapshot) {
          final groups = <ProductTaxGroupCatalogEntry>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final id = doc.id.trim();
            if (id.isEmpty) {
              continue;
            }

            final name = (data['name'] ?? data['nome'] ?? data['label'] ?? '')
                .toString();
            final description = (data['description'] ?? data['descricao'] ?? '')
                .toString()
                .trim();
            final status = (data['status'] ?? '').toString().trim();

            final entry = ProductTaxGroupCatalogEntry(
              id: id,
              name: name,
              description: description.isEmpty ? null : description,
              status: status.isEmpty ? null : status,
            );
            groups.add(entry);
          }

          groups.sort((a, b) {
            final aLabel = a.displayLabel.toLowerCase();
            final bLabel = b.displayLabel.toLowerCase();
            return aLabel.compareTo(bLabel);
          });
          return groups;
        });
  }
}
