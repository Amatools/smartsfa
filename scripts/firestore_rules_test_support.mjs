import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rules = await fs.readFile(path.resolve(__dirname, '../firestore.rules'), 'utf8');
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [host, portValue] = emulatorHost.split(':');
const port = Number.parseInt(portValue, 10);

export async function createTestContext() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'smartsfa-firestore-rules-smoke',
    firestore: {
      host,
      port,
      rules,
    },
  });

  return {
    testEnv,
    authContext(uid, email) {
      return testEnv.authenticatedContext(uid, { email }).firestore();
    },
    async cleanup() {
      await testEnv.cleanup();
    },
  };
}

export const ids = {
  repTenantId: 'self_owner_rep-a',
  ownerUid: 'owner-uid',
  repUid: 'rep-uid',
  sellerUid: 'seller-uid',
  soloUid: 'solo-uid',
  repInviteToRepId: 'invite-rep',
  repInviteToSellerId: 'invite-seller',
};

export function buildMembershipIds() {
  return {
    repMembershipOwnerId: `${ids.repTenantId}_${ids.ownerUid}`,
    repMembershipRepId: `${ids.repTenantId}_${ids.repUid}`,
    repMembershipSellerId: `${ids.repTenantId}_${ids.sellerUid}`,
    soloTenantId: `solo_${ids.soloUid}`,
    soloMembershipId: `solo_${ids.soloUid}_${ids.soloUid}`,
  };
}

export async function seedBaseData(testEnv) {
  const membershipIds = buildMembershipIds();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, 'usuarios', ids.ownerUid), {
      uid: ids.ownerUid,
      email: 'owner@test.local',
      displayName: 'Owner',
      platformRole: 'none',
      ativoGlobal: true,
      accountContractLock: 'flexible',
    });

    await setDoc(doc(db, 'usuarios', ids.repUid), {
      uid: ids.repUid,
      email: 'rep@test.local',
      displayName: 'Representante',
      platformRole: 'none',
      ativoGlobal: true,
      accountContractLock: 'flexible',
    });

    await setDoc(doc(db, 'usuarios', ids.sellerUid), {
      uid: ids.sellerUid,
      email: 'seller@test.local',
      displayName: 'Vendedor',
      platformRole: 'none',
      ativoGlobal: true,
      accountContractLock: 'flexible',
    });

    await setDoc(doc(db, 'usuarios', ids.soloUid), {
      uid: ids.soloUid,
      email: 'solo@test.local',
      displayName: 'Solo',
      platformRole: 'none',
      ativoGlobal: true,
      accountContractLock: 'flexible',
    });

    await setDoc(doc(db, 'tenants', ids.repTenantId), {
      tenantId: ids.repTenantId,
      slug: ids.repTenantId,
      nomeFantasia: 'Representacoes A',
      ativo: true,
      productSyncFromErpEnabled: false,
      operationMode: 'manual',
      erpProvider: 'none',
      workspaceType: 'rep_workspace',
      hierarchyModel: 'rep_to_seller',
      allowInvitations: true,
      cnpjBinding: 'informational_only',
      ownerUid: ids.ownerUid,
      plan: 'team',
      favoriteRepresentedCompanyId: '',
    });

    await setDoc(doc(db, 'tenants', membershipIds.soloTenantId), {
      tenantId: membershipIds.soloTenantId,
      slug: membershipIds.soloTenantId,
      nomeFantasia: 'Solo Workspace',
      ativo: true,
      productSyncFromErpEnabled: false,
      operationMode: 'manual',
      erpProvider: 'none',
      workspaceType: 'seller_solo_workspace',
      hierarchyModel: 'seller_only',
      allowInvitations: false,
      cnpjBinding: 'informational_only',
      ownerUid: ids.soloUid,
      plan: 'solo',
      favoriteRepresentedCompanyId: '',
    });

    await setDoc(doc(db, 'tenant_memberships', membershipIds.repMembershipOwnerId), {
      membershipId: membershipIds.repMembershipOwnerId,
      tenantId: ids.repTenantId,
      uid: ids.ownerUid,
      role: 'owner',
      ativo: true,
      defaultTenant: true,
      ownerId: ids.ownerUid,
      gerenteId: '',
      representanteId: '',
      vendedorId: '',
      state: 'active',
    });

    await setDoc(doc(db, 'tenant_memberships', membershipIds.repMembershipRepId), {
      membershipId: membershipIds.repMembershipRepId,
      tenantId: ids.repTenantId,
      uid: ids.repUid,
      role: 'representante',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: '',
      representanteId: ids.repUid,
      vendedorId: '',
      state: 'active',
    });

    await setDoc(doc(db, 'tenant_memberships', membershipIds.repMembershipSellerId), {
      membershipId: membershipIds.repMembershipSellerId,
      tenantId: ids.repTenantId,
      uid: ids.sellerUid,
      role: 'vendedor',
      ativo: true,
      defaultTenant: false,
      ownerId: ids.ownerUid,
      gerenteId: '',
      representanteId: ids.repUid,
      vendedorId: ids.sellerUid,
      state: 'active',
    });

    await setDoc(doc(db, 'tenant_memberships', membershipIds.soloMembershipId), {
      membershipId: membershipIds.soloMembershipId,
      tenantId: membershipIds.soloTenantId,
      uid: ids.soloUid,
      role: 'vendedor',
      ativo: true,
      defaultTenant: true,
      ownerId: '',
      gerenteId: '',
      representanteId: '',
      vendedorId: ids.soloUid,
      state: 'active',
    });
  });

  return membershipIds;
}