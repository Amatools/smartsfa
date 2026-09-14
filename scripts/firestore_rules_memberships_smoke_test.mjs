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

  await assertSucceeds(
    setDoc(doc(ownerDb, 'tenant_memberships', `${ids.repTenantId}_new-seller`), {
      membershipId: `${ids.repTenantId}_new-seller`,
      tenantId: ids.repTenantId,
      uid: 'new-seller',
      role: 'vendedor',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: '',
      representanteId: ids.repUid,
      vendedorId: 'new-seller',
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
      gerenteId: '',
      representanteId: ids.repUid,
      vendedorId: 'new-seller-2',
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
      state: 'active',
    }),
  );

  await assertSucceeds(getDoc(doc(ownerDb, 'tenant_memberships', membershipIds.repMembershipRepId)));
  await assertSucceeds(getDoc(doc(repDb, 'tenant_memberships', membershipIds.repMembershipSellerId)));
  await assertFails(getDoc(doc(sellerDb, 'tenant_memberships', membershipIds.repMembershipRepId)));

  console.log('Memberships and invitations smoke test passed.');
} finally {
  await cleanup();
}