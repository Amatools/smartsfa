import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';

import { createTestContext, ids, seedBaseData } from './firestore_rules_test_support.mjs';

const { authContext, cleanup, testEnv } = await createTestContext();
const membershipIds = await seedBaseData(testEnv);
const ownerDb = authContext(ids.ownerUid, 'owner@test.local');
const repDb = authContext(ids.repUid, 'rep@test.local');
const sellerDb = authContext(ids.sellerUid, 'seller@test.local');

try {
  await assertSucceeds(
    setDoc(doc(ownerDb, 'tenant_invitations', ids.repInviteToRepId), {
      token: ids.repInviteToRepId,
      tenantId: ids.repTenantId,
      role: 'representante',
      status: 'pending',
      invitedEmail: 'novo-rep@test.local',
      defaultTenant: false,
      createdByUid: ids.ownerUid,
    }),
  );

  await assertFails(
    setDoc(doc(repDb, 'tenant_invitations', ids.repInviteToSellerId), {
      token: ids.repInviteToSellerId,
      tenantId: ids.repTenantId,
      role: 'vendedor',
      status: 'pending',
      invitedEmail: 'novo-vendedor@test.local',
      defaultTenant: false,
      createdByUid: ids.repUid,
    }),
  );

  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'tenants', ids.repTenantId),
      {
        policy: {
          allowManagerDisableRepresentative: false,
          allowRepresentativeDisableSeller: true,
          allowManagerSendInvites: false,
          allowRepresentativeSendInvites: true,
          allowPersonalWorkspace: true,
        },
        updatedAt: new Date().toISOString(),
      },
      { merge: true },
    ),
  );

  await assertSucceeds(
    setDoc(doc(repDb, 'tenant_invitations', ids.repInviteToSellerId), {
      token: ids.repInviteToSellerId,
      tenantId: ids.repTenantId,
      role: 'vendedor',
      status: 'pending',
      invitedEmail: 'novo-vendedor@test.local',
      defaultTenant: false,
      createdByUid: ids.repUid,
    }),
  );

  await assertFails(
    setDoc(doc(repDb, 'tenant_invitations', 'invite-forged-created-by'), {
      token: 'invite-forged-created-by',
      tenantId: ids.repTenantId,
      role: 'vendedor',
      status: 'pending',
      invitedEmail: 'forged@test.local',
      defaultTenant: false,
      createdByUid: ids.ownerUid,
    }),
  );

  await assertFails(
    setDoc(doc(repDb, 'tenant_invitations', 'invite-rep-by-rep'), {
      token: 'invite-rep-by-rep',
      tenantId: ids.repTenantId,
      role: 'representante',
      status: 'pending',
      invitedEmail: 'bloqueado@test.local',
      defaultTenant: false,
      createdByUid: ids.repUid,
    }),
  );

  await assertFails(
    setDoc(doc(repDb, 'tenant_invitations', ids.repInviteToRepId), {
      token: ids.repInviteToRepId,
      tenantId: ids.repTenantId,
      role: 'representante',
      status: 'revoked',
      invitedEmail: 'novo-rep@test.local',
      defaultTenant: false,
      createdByUid: ids.ownerUid,
      revokedByUid: ids.repUid,
    }),
  );

  await assertSucceeds(
    getDoc(doc(ownerDb, 'tenant_invitations', ids.repInviteToRepId)),
  );
  await assertFails(
    getDoc(doc(repDb, 'tenant_invitations', ids.repInviteToRepId)),
  );
  await assertSucceeds(
    getDoc(doc(repDb, 'tenant_invitations', ids.repInviteToSellerId)),
  );

  await assertSucceeds(
    setDoc(doc(ownerDb, 'tenant_invitations', ids.repInviteToSellerId), {
      token: ids.repInviteToSellerId,
      tenantId: ids.repTenantId,
      role: 'vendedor',
      status: 'revoked',
      invitedEmail: 'novo-vendedor@test.local',
      defaultTenant: false,
      createdByUid: ids.repUid,
      revokedByUid: ids.ownerUid,
    }),
  );

  await assertSucceeds(
    setDoc(doc(ownerDb, 'tenant_memberships', `${ids.repTenantId}_new-seller`), {
      membershipId: `${ids.repTenantId}_new-seller`,
      tenantId: ids.repTenantId,
      uid: 'new-seller',
      role: 'vendedor',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: ids.ownerUid,
      representanteId: ids.repUid,
      vendedorId: 'new-seller',
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 0,
      state: 'active',
    }),
  );

  await assertSucceeds(
    setDoc(doc(repDb, 'tenant_memberships', `${ids.repTenantId}_new-seller-2`), {
      membershipId: `${ids.repTenantId}_new-seller-2`,
      tenantId: ids.repTenantId,
      uid: 'new-seller-2',
      role: 'vendedor',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: ids.ownerUid,
      representanteId: ids.repUid,
      vendedorId: 'new-seller-2',
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 0,
      state: 'active',
    }),
  );

  await assertFails(
    setDoc(doc(repDb, 'tenant_memberships', `${ids.repTenantId}_bad-rep`), {
      membershipId: `${ids.repTenantId}_bad-rep`,
      tenantId: ids.repTenantId,
      uid: 'bad-rep',
      role: 'representante',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: '',
      representanteId: 'bad-rep',
      vendedorId: '',
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 0,
      state: 'active',
    }),
  );

  await assertSucceeds(getDoc(doc(ownerDb, 'tenant_memberships', membershipIds.repMembershipRepId)));
  await assertSucceeds(getDoc(doc(repDb, 'tenant_memberships', membershipIds.repMembershipSellerId)));
  await assertFails(getDoc(doc(sellerDb, 'tenant_memberships', membershipIds.repMembershipRepId)));

  await assertFails(
    setDoc(doc(ownerDb, 'tenant_memberships', membershipIds.repMembershipRepId), {
      membershipId: membershipIds.repMembershipRepId,
      tenantId: ids.repTenantId,
      uid: ids.repUid,
      role: 'vendedor',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: ids.ownerUid,
      representanteId: ids.repUid,
      vendedorId: ids.repUid,
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 0,
      state: 'active',
    }),
  );

  const enterpriseTenantId = `self_${ids.ownerUid}_enterprise-rule-guard`;
  const managerUid = 'manager-uid';
  const representativeUid = 'rep-enterprise-uid';
  const managerMembershipId = `${enterpriseTenantId}_${managerUid}`;

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'usuarios', managerUid), {
      uid: managerUid,
      email: 'manager@test.local',
      displayName: 'Manager',
      platformRole: 'none',
      ativoGlobal: true,
      accountContractLock: 'flexible',
    });

    await setDoc(doc(db, 'usuarios', representativeUid), {
      uid: representativeUid,
      email: 'rep-enterprise@test.local',
      displayName: 'Representative Enterprise',
      platformRole: 'none',
      ativoGlobal: true,
      accountContractLock: 'flexible',
    });

    await setDoc(doc(db, 'tenants', enterpriseTenantId), {
      tenantId: enterpriseTenantId,
      slug: enterpriseTenantId,
      nomeFantasia: 'Enterprise Guard Tenant',
      ativo: true,
      productSyncFromErpEnabled: false,
      operationMode: 'manual',
      erpProvider: 'none',
      workspaceType: 'brand_owner_workspace',
      hierarchyModel: 'full_chain',
      allowInvitations: true,
      cnpjBinding: 'owner_legal_entity',
      ownerUid: ids.ownerUid,
      plan: 'enterprise',
    });

    await setDoc(doc(db, 'tenant_memberships', `${enterpriseTenantId}_${ids.ownerUid}`), {
      membershipId: `${enterpriseTenantId}_${ids.ownerUid}`,
      tenantId: enterpriseTenantId,
      uid: ids.ownerUid,
      role: 'owner',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: ids.ownerUid,
      representanteId: ids.ownerUid,
      vendedorId: ids.ownerUid,
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 0,
      state: 'active',
    });

    await setDoc(doc(db, 'tenant_memberships', managerMembershipId), {
      membershipId: managerMembershipId,
      tenantId: enterpriseTenantId,
      uid: managerUid,
      role: 'gerente',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: managerUid,
      representanteId: managerUid,
      vendedorId: managerUid,
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 1,
      activeSubordinateCount: 1,
      state: 'active',
    });

    await setDoc(doc(db, 'tenant_memberships', `${enterpriseTenantId}_${representativeUid}`), {
      membershipId: `${enterpriseTenantId}_${representativeUid}`,
      tenantId: enterpriseTenantId,
      uid: representativeUid,
      role: 'representante',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: managerUid,
      representanteId: representativeUid,
      vendedorId: representativeUid,
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 0,
      state: 'active',
    });
  });

  await assertFails(
    setDoc(doc(ownerDb, 'tenant_memberships', managerMembershipId), {
      membershipId: managerMembershipId,
      tenantId: enterpriseTenantId,
      uid: managerUid,
      role: 'representante',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: managerUid,
      representanteId: managerUid,
      vendedorId: managerUid,
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 1,
      activeSubordinateCount: 1,
      state: 'active',
    }),
  );

  await assertFails(
    setDoc(doc(ownerDb, 'tenant_memberships', managerMembershipId), {
      membershipId: managerMembershipId,
      tenantId: enterpriseTenantId,
      uid: managerUid,
      role: 'gerente',
      ativo: false,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: managerUid,
      representanteId: managerUid,
      vendedorId: managerUid,
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 1,
      activeSubordinateCount: 1,
      state: 'revoked',
    }),
  );

  const movementId = `${ids.repTenantId}_movement_1`;
  await assertSucceeds(
    setDoc(doc(ownerDb, 'tenant_hierarchy_movements', movementId), {
      movementId,
      tenantId: ids.repTenantId,
      subjectUid: ids.sellerUid,
      subjectRole: 'vendedor',
      fromOwnerId: ids.ownerUid,
      fromGerenteId: ids.ownerUid,
      fromRepresentanteId: ids.repUid,
      fromVendedorId: ids.sellerUid,
      toOwnerId: ids.ownerUid,
      toGerenteId: ids.ownerUid,
      toRepresentanteId: ids.ownerUid,
      toVendedorId: ids.sellerUid,
      reason: 'manual_reallocation',
      actorUid: ids.ownerUid,
      createdAt: new Date().toISOString(),
    }),
  );

  await assertFails(
    setDoc(doc(repDb, 'tenant_hierarchy_movements', `${ids.repTenantId}_movement_2`), {
      movementId: `${ids.repTenantId}_movement_2`,
      tenantId: ids.repTenantId,
      subjectUid: ids.sellerUid,
      subjectRole: 'vendedor',
      fromOwnerId: ids.ownerUid,
      fromGerenteId: ids.ownerUid,
      fromRepresentanteId: ids.repUid,
      fromVendedorId: ids.sellerUid,
      toOwnerId: ids.ownerUid,
      toGerenteId: ids.ownerUid,
      toRepresentanteId: ids.repUid,
      toVendedorId: ids.sellerUid,
      reason: 'rep_reallocation_attempt',
      actorUid: ids.repUid,
      createdAt: new Date().toISOString(),
    }),
  );

  await assertSucceeds(
    getDoc(doc(ownerDb, 'tenant_hierarchy_movements', movementId)),
  );
  await assertFails(
    getDoc(doc(repDb, 'tenant_hierarchy_movements', movementId)),
  );

  console.log('Memberships and invitations smoke test passed.');
} finally {
  await cleanup();
}