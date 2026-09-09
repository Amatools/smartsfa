import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

async function run() {
  const serviceAccountPath = required('GOOGLE_APPLICATION_CREDENTIALS_JSON');
  const tenantId = required('TENANT_ID');
  const tenantSlug = required('TENANT_SLUG');
  const tenantName = required('TENANT_NAME');
  const ownerEmail = required('OWNER_EMAIL');
  const ownerPassword = process.env.OWNER_PASSWORD;
  const ownerName = process.env.OWNER_NAME ?? 'Owner SmartSFA';
  const operationMode = process.env.TENANT_OPERATION_MODE ?? 'manual';
  const erpProvider = process.env.TENANT_ERP_PROVIDER ?? 'none';

  const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, 'utf8'));

  initializeApp({
    credential: cert(serviceAccount),
  });

  const auth = getAuth();
  const db = getFirestore();

  let user;
  try {
    user = await auth.getUserByEmail(ownerEmail);
  } catch {
    user = await auth.createUser({
      email: ownerEmail,
      password: ownerPassword,
      emailVerified: true,
      displayName: ownerName,
    });
  }

  await auth.setCustomUserClaims(user.uid, {
    platformRole: 'none',
    ativoGlobal: true,
  });

  const membershipId = `${tenantId}_${user.uid}`;

  await db.collection('tenants').doc(tenantId).set(
    {
      tenantId,
      slug: tenantSlug,
      nomeFantasia: tenantName,
      ativo: true,
      onboardingStatus: 'active',
      operationMode,
      erpProvider,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await db.collection('usuarios').doc(user.uid).set(
    {
      uid: user.uid,
      email: ownerEmail,
      displayName: user.displayName ?? ownerName,
      platformRole: 'none',
      ativoGlobal: true,
      defaultTenantId: tenantId,
      sankhyaPartnerIds: [],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await db.collection('tenant_memberships').doc(membershipId).set(
    {
      membershipId,
      tenantId,
      uid: user.uid,
      role: 'owner',
      ativo: true,
      defaultTenant: true,
      ownerId: user.uid,
      gerenteId: '',
      representanteId: '',
      vendedorId: '',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  console.log('Tenant and owner provisioned successfully.');
  console.log(`tenantId: ${tenantId}`);
  console.log(`tenantSlug: ${tenantSlug}`);
  console.log(`uid: ${user.uid}`);
  console.log(`email: ${ownerEmail}`);
}

run().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
