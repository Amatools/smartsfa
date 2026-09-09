import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/features/tenant/domain/tenant_membership_audit_filter.dart';

void main() {
  final entries = <Map<String, dynamic>>[
    {
      'action': 'membership_revoked',
      'actorUid': 'owner_1',
      'membershipId': 'tenant_a_u1',
    },
    {
      'action': 'membership_reactivated',
      'actorUid': 'manager_1',
      'membershipId': 'tenant_a_u2',
    },
    {
      'action': 'tenant_policy_updated',
      'actorUid': 'owner_1',
      'membershipId': '',
    },
  ];

  test('filters by selected action', () {
    final result = TenantMembershipAuditFilter.apply(
      entries: entries,
      query: '',
      selectedAction: 'membership_reactivated',
    );

    expect(result, hasLength(1));
    expect(result.first['actorUid'], 'manager_1');
  });

  test('filters by text query across action, actorUid and membershipId', () {
    final byAction = TenantMembershipAuditFilter.apply(
      entries: entries,
      query: 'policy',
      selectedAction: 'todos',
    );
    final byActor = TenantMembershipAuditFilter.apply(
      entries: entries,
      query: 'owner_1',
      selectedAction: 'todos',
    );
    final byMembership = TenantMembershipAuditFilter.apply(
      entries: entries,
      query: 'tenant_a_u2',
      selectedAction: 'todos',
    );

    expect(byAction, hasLength(1));
    expect(byAction.first['action'], 'tenant_policy_updated');

    expect(byActor, hasLength(2));
    expect(byMembership, hasLength(1));
    expect(byMembership.first['action'], 'membership_reactivated');
  });
}
