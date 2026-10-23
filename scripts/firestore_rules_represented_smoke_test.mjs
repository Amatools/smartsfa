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
    setDoc(doc(ownerDb, 'tenant_represented_companies', `${ids.repTenantId}_acme`), {
      tenantId: ids.repTenantId,
      companyId: 'acme',
      nomeFantasia: 'ACME',
      razaoSocial: '',
      cnpj: '07.228.424/0001-57',
      cep: '',
      logoUrl: '',
      contato: '',
      telefone: '',
      email: '',
      cidade: '',
      uf: 'SP',
      segmento: '',
      taxRegime: 'simples_nacional',
      parentCompanyId: '',
      ativo: true,
    }),
  );

  await assertSucceeds(
    setDoc(doc(repDb, 'tenant_represented_companies', `${ids.repTenantId}_beta`), {
      tenantId: ids.repTenantId,
      companyId: 'beta',
      nomeFantasia: 'Beta',
      razaoSocial: '',
      cnpj: '11.111.111/0001-91',
      cep: '',
      logoUrl: '',
      contato: '',
      telefone: '',
      email: '',
      cidade: '',
      uf: 'SP',
      segmento: '',
      taxRegime: 'simples_nacional',
      parentCompanyId: '',
      ativo: true,
    }),
  );

  await assertFails(
    setDoc(doc(sellerDb, 'tenant_represented_companies', `${ids.repTenantId}_gamma`), {
      tenantId: ids.repTenantId,
      companyId: 'gamma',
      nomeFantasia: 'Gamma',
      razaoSocial: '',
      cnpj: '22.222.222/0001-72',
      cep: '',
      logoUrl: '',
      contato: '',
      telefone: '',
      email: '',
      cidade: '',
      uf: 'SP',
      segmento: '',
      taxRegime: 'simples_nacional',
      parentCompanyId: '',
      ativo: true,
    }),
  );

  await assertSucceeds(
    updateDoc(doc(repDb, 'tenants', ids.repTenantId), {
      favoriteRepresentedCompanyId: 'beta',
    }),
  );

  await assertSucceeds(
    updateDoc(doc(soloDb, 'tenants', membershipIds.soloTenantId), {
      favoriteRepresentedCompanyId: 'solo-favorite',
    }),
  );

  await assertFails(
    updateDoc(doc(sellerDb, 'tenants', ids.repTenantId), {
      favoriteRepresentedCompanyId: 'gamma',
    }),
  );

  console.log('Represented companies smoke test passed.');
} finally {
  await cleanup();
}