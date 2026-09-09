import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartsfa/src/core/models/app_identity.dart';
import 'package:smartsfa/src/features/auth/services/tenant_membership_service.dart';
import 'package:smartsfa/src/features/tenant/presentation/pages/tenant_admin_page.dart';

void main() {
  group('TenantAdminPage', () {
    late FakeFirebaseFirestore firestore;
    late TenantMembershipService membershipService;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      membershipService = TenantMembershipService(firestore);
    });

    testWidgets('owner can revoke vendedor membership', (tester) async {
      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_owner_uid',
        tenantId: 'tenant_a',
        uid: 'owner_uid',
        role: 'owner',
        ativo: true,
        state: 'active',
      );
      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_vendedor_uid',
        tenantId: 'tenant_a',
        uid: 'vendedor_uid',
        role: 'vendedor',
        ativo: true,
        state: 'active',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TenantAdminPage(
              identity: const AppIdentity(
                tenantId: 'tenant_a',
                userLabel: 'owner@empresa.com',
                role: 'owner',
                tenantName: 'Tenant A',
                isMock: false,
              ),
              membershipService: membershipService,
              currentUserUid: 'owner_uid',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final revokeButton = find.byKey(const Key('revoke_tenant_a_vendedor_uid'));
      expect(revokeButton, findsOneWidget);
      await tester.ensureVisible(revokeButton);
      await tester.tap(revokeButton);
      await tester.pumpAndSettle();

      final doc = await firestore
          .collection('tenant_memberships')
          .doc('tenant_a_vendedor_uid')
          .get();
      expect(doc.data()?['state'], 'revoked');
      expect(doc.data()?['ativo'], false);
    });

    testWidgets('owner cannot revoke another owner membership', (tester) async {
      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_owner_uid',
        tenantId: 'tenant_a',
        uid: 'owner_uid',
        role: 'owner',
        ativo: true,
        state: 'active',
      );
      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_owner_2',
        tenantId: 'tenant_a',
        uid: 'owner_2',
        role: 'owner',
        ativo: true,
        state: 'active',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TenantAdminPage(
              identity: const AppIdentity(
                tenantId: 'tenant_a',
                userLabel: 'owner@empresa.com',
                role: 'owner',
                tenantName: 'Tenant A',
                isMock: false,
              ),
              membershipService: membershipService,
              currentUserUid: 'owner_uid',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final buttonWidget = tester.widget<OutlinedButton>(
        find.byKey(const Key('revoke_tenant_a_owner_2')),
      );
      expect(buttonWidget.onPressed, isNull);
    });

    testWidgets('platform admin can reactivate revoked membership', (tester) async {
      await firestore.collection('usuarios').doc('admin_uid').set({
        'uid': 'admin_uid',
        'email': 'admin@plataforma.com',
        'platformRole': 'platform_admin',
      });

      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_owner_uid',
        tenantId: 'tenant_a',
        uid: 'owner_uid',
        role: 'owner',
        ativo: true,
        state: 'active',
      );
      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_revoked_uid',
        tenantId: 'tenant_a',
        uid: 'revoked_uid',
        role: 'vendedor',
        ativo: false,
        state: 'revoked',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TenantAdminPage(
              identity: const AppIdentity(
                tenantId: 'tenant_a',
                userLabel: 'admin@plataforma.com',
                role: 'platform_admin',
                tenantName: 'Tenant A',
                isMock: false,
              ),
              membershipService: membershipService,
              currentUserUid: 'admin_uid',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final reactivateButton = find.byKey(const Key('reactivate_tenant_a_revoked_uid'));
      expect(reactivateButton, findsOneWidget);
      await tester.ensureVisible(reactivateButton);
      await tester.tap(reactivateButton);
      await tester.pumpAndSettle();

      final doc = await firestore
          .collection('tenant_memberships')
          .doc('tenant_a_revoked_uid')
          .get();
      expect(doc.data()?['state'], 'active');
      expect(doc.data()?['ativo'], true);
    });

    testWidgets('owner can change vendedor role to gerente', (tester) async {
      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_owner_uid',
        tenantId: 'tenant_a',
        uid: 'owner_uid',
        role: 'owner',
        ativo: true,
        state: 'active',
      );
      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_vendedor_to_promote',
        tenantId: 'tenant_a',
        uid: 'vendedor_uid',
        role: 'vendedor',
        ativo: true,
        state: 'active',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TenantAdminPage(
              identity: const AppIdentity(
                tenantId: 'tenant_a',
                userLabel: 'owner@empresa.com',
                role: 'owner',
                tenantName: 'Tenant A',
                isMock: false,
              ),
              membershipService: membershipService,
              currentUserUid: 'owner_uid',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final changeRoleButton =
          find.byKey(const Key('change_role_tenant_a_vendedor_to_promote'));
      expect(changeRoleButton, findsOneWidget);
      await tester.ensureVisible(changeRoleButton);
      await tester.tap(changeRoleButton);
      await tester.pumpAndSettle();

      final gerenteOption = find.byKey(
        const Key('change_role_tenant_a_vendedor_to_promote_gerente'),
      );
      expect(gerenteOption, findsOneWidget);
      await tester.tap(gerenteOption);
      await tester.pumpAndSettle();

      final doc = await firestore
          .collection('tenant_memberships')
          .doc('tenant_a_vendedor_to_promote')
          .get();

      expect(doc.data()?['role'], 'gerente');
      expect(doc.data()?['gerenteId'], 'vendedor_uid');
      expect(doc.data()?['vendedorId'], '');
    });

    testWidgets('owner cannot see owner role option in change role', (tester) async {
      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_owner_uid',
        tenantId: 'tenant_a',
        uid: 'owner_uid',
        role: 'owner',
        ativo: true,
        state: 'active',
      );
      await _seedMembership(
        firestore,
        membershipId: 'tenant_a_representante_uid',
        tenantId: 'tenant_a',
        uid: 'representante_uid',
        role: 'representante',
        ativo: true,
        state: 'active',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TenantAdminPage(
              identity: const AppIdentity(
                tenantId: 'tenant_a',
                userLabel: 'owner@empresa.com',
                role: 'owner',
                tenantName: 'Tenant A',
                isMock: false,
              ),
              membershipService: membershipService,
              currentUserUid: 'owner_uid',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final changeRoleButton =
          find.byKey(const Key('change_role_tenant_a_representante_uid'));
      expect(changeRoleButton, findsOneWidget);
      await tester.ensureVisible(changeRoleButton);
      await tester.tap(changeRoleButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('change_role_tenant_a_representante_uid_owner')),
        findsNothing,
      );
    });
  });
}

Future<void> _seedMembership(
  FakeFirebaseFirestore firestore, {
  required String membershipId,
  required String tenantId,
  required String uid,
  required String role,
  required bool ativo,
  required String state,
}) {
  return firestore.collection('tenant_memberships').doc(membershipId).set({
    'membershipId': membershipId,
    'tenantId': tenantId,
    'uid': uid,
    'role': role,
    'ativo': ativo,
    'defaultTenant': false,
    'ownerId': '',
    'gerenteId': '',
    'representanteId': '',
    'vendedorId': '',
    'state': state,
  });
}
