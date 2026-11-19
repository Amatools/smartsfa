import 'package:flutter_test/flutter_test.dart';

import 'package:smartsfa/src/core/models/tenant_membership.dart';

void main() {
  group('TenantMembership.toMap', () {
    test('omits inactivity fields when they are null', () {
      const membership = TenantMembership(
        membershipId: 'tenant_a_u1',
        tenantId: 'tenant_a',
        uid: 'u1',
        role: 'representante',
        ativo: false,
        defaultTenant: false,
        ownerId: 'owner_1',
        gerenteId: 'owner_1',
        representanteId: 'u1',
        vendedorId: 'u1',
      );

      final map = membership.toMap();

      expect(map.containsKey('inactivityStartAt'), isFalse);
      expect(map.containsKey('inactivityEndAt'), isFalse);
      expect(map.containsKey('inactivityReason'), isFalse);
      expect(map.containsKey('inactivityUpdatedByUid'), isFalse);
      expect(map.containsKey('inactivityUpdatedAt'), isFalse);
    });

    test('includes inactivity fields when dates are set', () {
      final start = DateTime.utc(2026, 11, 1);
      final end = DateTime.utc(2026, 11, 10);
      final updatedAt = DateTime.utc(2026, 11, 2, 12, 30);

      final membership = TenantMembership(
        membershipId: 'tenant_a_u1',
        tenantId: 'tenant_a',
        uid: 'u1',
        role: 'representante',
        ativo: false,
        defaultTenant: false,
        ownerId: 'owner_1',
        gerenteId: 'owner_1',
        representanteId: 'u1',
        vendedorId: 'u1',
        inactivityStartAt: start,
        inactivityEndAt: end,
        inactivityReason: 'ferias',
        inactivityUpdatedByUid: 'owner_1',
        inactivityUpdatedAt: updatedAt,
      );

      final map = membership.toMap();

      expect(map['inactivityStartAt'], start.toIso8601String());
      expect(map['inactivityEndAt'], end.toIso8601String());
      expect(map['inactivityReason'], 'ferias');
      expect(map['inactivityUpdatedByUid'], 'owner_1');
      expect(map['inactivityUpdatedAt'], updatedAt.toIso8601String());
    });
  });
}
