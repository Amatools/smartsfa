import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';

import { createTestContext, ids, seedBaseData } from './firestore_rules_test_support.mjs';

const { authContext, cleanup, testEnv } = await createTestContext();
const membershipIds = await seedBaseData(testEnv);
const ownerDb = authContext(ids.ownerUid, 'owner@test.local');
const repDb = authContext(ids.repUid, 'rep@test.local');
const sellerDb = authContext(ids.sellerUid, 'seller@test.local');
const soloDb = authContext(ids.soloUid, 'solo@test.local');

try {
  await assertSucceeds(
    setDoc(doc(ownerDb, 'tenants', `self_${ids.ownerUid}_nova-operacao`), {
      tenantId: `self_${ids.ownerUid}_nova-operacao`,
      slug: `self_${ids.ownerUid}_nova-operacao`,
      nomeFantasia: 'Nova Operacao',
      razaoSocial: 'Nova Operacao LTDA',
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
    }),
  );

  await assertSucceeds(
    setDoc(doc(soloDb, 'tenants', membershipIds.soloTenantId), {
      tenantId: membershipIds.soloTenantId,
      slug: membershipIds.soloTenantId,
      nomeFantasia: 'Solo Workspace Atualizado',
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
    }),
  );

  await assertFails(
    setDoc(doc(sellerDb, 'tenants', `self_${ids.sellerUid}_workspace-ilegal`), {
      tenantId: `self_${ids.sellerUid}_workspace-ilegal`,
      slug: `self_${ids.sellerUid}_workspace-ilegal`,
      nomeFantasia: 'Workspace Ilegal',
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
    }),
  );

  await assertSucceeds(
    updateDoc(doc(ownerDb, 'tenants', ids.repTenantId), {
      nomeFantasia: 'Representacoes A Atualizado',
    }),
  );

  await assertFails(
    updateDoc(doc(repDb, 'tenants', ids.repTenantId), {
      nomeFantasia: 'Nao Pode Atualizar Tenant',
    }),
  );

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'usuarios', 'enterprise-locked-uid'), {
      uid: 'enterprise-locked-uid',
      email: 'locked@test.local',
      displayName: 'Locked',
      platformRole: 'none',
      ativoGlobal: true,
      accountContractLock: 'enterprise_only',
    });
  });

  const lockedDb = authContext('enterprise-locked-uid', 'locked@test.local');

  await assertFails(
    setDoc(doc(lockedDb, 'tenants', 'self_enterprise-locked-uid_rep-bloqueado'), {
      tenantId: 'self_enterprise-locked-uid_rep-bloqueado',
      slug: 'self_enterprise-locked-uid_rep-bloqueado',
      nomeFantasia: 'Rep Bloqueado',
      ativo: true,
      productSyncFromErpEnabled: false,
      operationMode: 'manual',
      erpProvider: 'none',
      workspaceType: 'rep_workspace',
      hierarchyModel: 'rep_to_seller',
      allowInvitations: true,
      cnpjBinding: 'informational_only',
      ownerUid: 'enterprise-locked-uid',
      plan: 'team',
    }),
  );

  await assertSucceeds(
    setDoc(doc(lockedDb, 'tenants', 'self_enterprise-locked-uid_brandop-ok'), {
      tenantId: 'self_enterprise-locked-uid_brandop-ok',
      slug: 'self_enterprise-locked-uid_brandop-ok',
      nomeFantasia: 'BrandOp Ok',
      ativo: true,
      productSyncFromErpEnabled: true,
      operationMode: 'manual',
      erpProvider: 'none',
      workspaceType: 'brand_owner_workspace',
      hierarchyModel: 'full_chain',
      allowInvitations: true,
      cnpjBinding: 'owner_legal_entity',
      ownerUid: 'enterprise-locked-uid',
      plan: 'enterprise',
    }),
  );

  console.log('Tenants smoke test passed.');
} finally {
  await cleanup();
}