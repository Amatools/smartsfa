import 'domain_types.dart';

class ClienteReference {
  const ClienteReference({
    required this.id,
    required this.type,
    required this.documentoSnapshot,
    required this.nomeSnapshot,
  });

  factory ClienteReference.fromMap(Map<String, Object?> map) {
    return ClienteReference(
      id: map['id'] as String? ?? '',
      type: CustomerReferenceType.fromValue(
        map['type'] as String? ?? CustomerReferenceType.official.value,
      ),
      documentoSnapshot: map['documentoSnapshot'] as String? ?? '',
      nomeSnapshot: map['nomeSnapshot'] as String? ?? '',
    );
  }

  final String id;
  final CustomerReferenceType type;
  final String documentoSnapshot;
  final String nomeSnapshot;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': type.value,
      'documentoSnapshot': documentoSnapshot,
      'nomeSnapshot': nomeSnapshot,
    };
  }
}