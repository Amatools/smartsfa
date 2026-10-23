import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Force direct local emulator traffic. Some environments inject HTTP(S)
// proxies that redirect localhost fetches and break rules loading.
process.env.NO_PROXY = '127.0.0.1,localhost,::1';
process.env.no_proxy = process.env.NO_PROXY;
process.env.HTTP_PROXY = '';
process.env.HTTPS_PROXY = '';
process.env.ALL_PROXY = '';
if (!process.env.NODE_TLS_REJECT_UNAUTHORIZED) {
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = '1';
}

function resolveEmulatorHostAndPort() {
  const raw = String(process.env.FIRESTORE_EMULATOR_HOST || '').trim();
  if (!raw) {
    return { host: '127.0.0.1', port: 8080 };
  }

  let host = '';
  let port = Number.NaN;

  try {
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      const parsed = new URL(raw);
      host = parsed.hostname;
      port = Number.parseInt(parsed.port || '8080', 10);
    } else {
      const idx = raw.lastIndexOf(':');
      if (idx > 0) {
        host = raw.slice(0, idx).trim();
        port = Number.parseInt(raw.slice(idx + 1).trim(), 10);
      } else {
        host = raw;
      }
    }
  } catch (_) {
    host = '';
    port = Number.NaN;
  }

  if (!host) {
    host = '127.0.0.1';
  }
  const localHosts = new Set(['127.0.0.1', 'localhost', '::1']);
  if (!localHosts.has(host.toLowerCase())) {
    host = '127.0.0.1';
  }
  if (!Number.isFinite(port) || port <= 0) {
    port = 8080;
  }

  return { host, port };
}

const { host, port } = resolveEmulatorHostAndPort();

export async function createTestContext() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'smartsfa-firestore-rules-smoke',
    firestore: {
      host,
      port,
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
      policy: {
        allowManagerDisableRepresentative: false,
        allowRepresentativeDisableSeller: true,
        allowManagerSendInvites: false,
        allowRepresentativeSendInvites: false,
        allowPersonalWorkspace: true,
      },
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
      gerenteId: ids.ownerUid,
      representanteId: ids.ownerUid,
      vendedorId: ids.ownerUid,
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 0,
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
      gerenteId: ids.ownerUid,
      representanteId: ids.repUid,
      vendedorId: ids.repUid,
      activeSellerChildrenCount: 1,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 1,
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
      gerenteId: ids.ownerUid,
      representanteId: ids.repUid,
      vendedorId: ids.sellerUid,
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 0,
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
      activeSellerChildrenCount: 0,
      activeRepresentativeChildrenCount: 0,
      activeSubordinateCount: 0,
      state: 'active',
    });
  });

  return membershipIds;
}