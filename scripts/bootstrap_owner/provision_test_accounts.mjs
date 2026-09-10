// Provisiona um tenant de teste + os 4 papeis (owner/gerente/representante/vendedor)
// para contas de usuario ja existentes no Firebase Auth do projeto smart-sfa.
//
// Uso:
//   1) Gere uma service account (Console Firebase > Configuracoes do projeto >
//      Contas de servico > Gerar nova chave privada) e salve o JSON em algum lugar.
//   2) set GOOGLE_APPLICATION_CREDENTIALS_JSON=caminho\para\service-account.json
//   3) node provision_test_accounts.mjs
//
// Requer "npm install" nesta pasta (usa firebase-admin).
import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const TENANT_ID = process.env.TENANT_ID ?? 'smartsfa_demo';
const TENANT_SLUG = process.env.TENANT_SLUG ?? 'smartsfa-demo';
const TENANT_NAME = process.env.TENANT_NAME ?? 'Smart SFA (Demo)';

const ACCOUNTS = [
  { role: 'owner', email: 'owner@smartsfa.com.br' },
  { role: 'gerente', email: 'gerente@smartsfa.com.br' },
  { role: 'representante', email: 'resepresentante@smartsfa.com.br' },
  { role: 'vendedor', email: 'vendedor@smartsfa.com.br' },
];

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

async function run() {
  const serviceAccountPath = required('GOOGLE_APPLICATION_CREDENTIALS_JSON');
  const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, 'utf8'));

  initializeApp({ credential: cert(serviceAccount) });

  const auth = getAuth();
  const db = getFirestore();

  // Resolve every account's uid from Firebase Auth first (all must already exist).
  const resolved = {};
  for (const account of ACCOUNTS) {
    const user = await auth.getUserByEmail(account.email);
    resolved[account.role] = { ...account, uid: user.uid, displayName: user.displayName ?? account.role };
  }

  const ownerId = resolved.owner.uid;
  const gerenteId = resolved.gerente.uid;
  const representanteId = resolved.representante.uid;
  const vendedorId = resolved.vendedor.uid;

  await db.collection('tenants').doc(TENANT_ID).set(
    {
      tenantId: TENANT_ID,
      slug: TENANT_SLUG,
      nomeFantasia: TENANT_NAME,
      ativo: true,
      operationMode: 'manual',
      erpProvider: 'none',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const hierarchy = {
    owner: { ownerId, gerenteId: '', representanteId: '', vendedorId: '' },
    gerente: { ownerId, gerenteId, representanteId: '', vendedorId: '' },
    representante: { ownerId, gerenteId, representanteId, vendedorId: '' },
    vendedor: { ownerId, gerenteId, representanteId, vendedorId },
  };

  for (const role of ['owner', 'gerente', 'representante', 'vendedor']) {
    const account = resolved[role];
    const scope = hierarchy[role];
    const membershipId = `${TENANT_ID}_${account.uid}`;

    await db.collection('usuarios').doc(account.uid).set(
      {
        uid: account.uid,
        email: account.email,
        displayName: account.displayName,
        platformRole: 'none',
        ativoGlobal: true,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await db.collection('tenant_memberships').doc(membershipId).set(
      {
        membershipId,
        tenantId: TENANT_ID,
        uid: account.uid,
        role,
        ativo: true,
        defaultTenant: true,
        state: 'active',
        ownerId: scope.ownerId,
        gerenteId: scope.gerenteId,
        representanteId: scope.representanteId,
        vendedorId: scope.vendedorId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    console.log(`OK: ${role} -> uid=${account.uid} email=${account.email}`);
  }

  console.log('\nTenant e papeis provisionados com sucesso.');
  console.log(`tenantId: ${TENANT_ID}`);
}

run().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
