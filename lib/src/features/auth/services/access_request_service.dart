import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/models/access_request.dart';

class AccessRequestService {
  AccessRequestService(this._firestore);

  final FirebaseFirestore _firestore;

  Future<AccessRequest?> load(User user) async {
    final doc = await _firestore.collection('solicitacoes_acesso').doc(user.uid).get();
    if (!doc.exists) {
      return null;
    }

    return AccessRequest.fromMap(doc.data() ?? <String, Object?>{});
  }

  Future<AccessRequest> upsertPending({
    required User user,
    String? tenantSlugOuConvite,
  }) async {
    final request = AccessRequest(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
      tenantSlugOuConvite: tenantSlugOuConvite,
      status: AccessRequestStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _firestore.collection('solicitacoes_acesso').doc(user.uid).set(
          request.toMap(),
          SetOptions(merge: true),
        );

    return request;
  }
}