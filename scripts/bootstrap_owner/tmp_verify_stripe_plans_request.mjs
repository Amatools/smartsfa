import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SERVICE_ACCOUNT_PATH = path.join(
  __dirname,
  'smart-sfa-firebase-adminsdk-fbsvc-d0361355cb.json',
);
const WEB_API_KEY = 'AIzaSyDFXV_T5_WfN2xrl-qi814i_AwReyGjXKs';
const LIST_STRIPE_CATALOG_URL =
  'https://us-central1-smart-sfa.cloudfunctions.net/listStripeCatalog';
const LIST_STRIPE_CHECKOUT_PLANS_URL =
  'https://us-central1-smart-sfa.cloudfunctions.net/listStripeCheckoutPlans';

function normalizeText(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

async function fetchJson(url, body, idToken) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify(body),
  });

  let payload = {};
  try {
    payload = await response.json();
  } catch (_) {
    payload = {};
  }

  return { status: response.status, payload };
}

async function main() {
  const serviceAccount = JSON.parse(
    fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'),
  );

  if (!getApps().length) {
    initializeApp({
      credential: cert(serviceAccount),
      projectId: 'smart-sfa',
    });
  }

  const auth = getAuth();
  const db = getFirestore();

  const platformAdminsSnapshot = await db
    .collection('usuarios')
    .where('platformRole', '==', 'platform_admin')
    .where('ativoGlobal', '==', true)
    .limit(1)
    .get();

  if (platformAdminsSnapshot.empty) {
    throw new Error('Nenhum usuario platform_admin ativo encontrado em usuarios.');
  }

  const platformAdminUid = platformAdminsSnapshot.docs[0].id;
  const customToken = await auth.createCustomToken(platformAdminUid);

  const signInResponse = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${WEB_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    },
  );

  const signInPayload = await signInResponse.json();
  if (!signInResponse.ok || !signInPayload.idToken) {
    throw new Error(
      `Falha ao trocar custom token por ID token. HTTP ${signInResponse.status}: ${JSON.stringify(signInPayload)}`,
    );
  }

  const idToken = String(signInPayload.idToken);

  const catalogResult = await fetchJson(
    LIST_STRIPE_CATALOG_URL,
    {
      activeOnly: false,
      limitProducts: 100,
      limitPricesPerProduct: 100,
    },
    idToken,
  );

  const planMappingsSnapshot = await db
    .collection('billing_integrations')
    .doc('stripe')
    .collection('plan_mappings')
    .where('active', '==', true)
    .get();

  const mappings = planMappingsSnapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));

  const representacoesMappings = mappings.filter((item) =>
    normalizeText(item.billingPlanKey).includes('representa') ||
    normalizeText(item.planDisplayName).includes('representa') ||
    normalizeText(item.stripeProductName).includes('representa'),
  );

  const representacoesBase = representacoesMappings.filter(
    (item) => String(item.mappingType ?? '').toLowerCase() === 'base',
  );
  const representacoesAddon = representacoesMappings.filter(
    (item) =>
      String(item.mappingType ?? '').toLowerCase() === 'overage' &&
      String(item.overageMetric ?? '').toLowerCase() === 'extra_usuario',
  );

  const repTenantSnapshot = await db
    .collection('tenants')
    .where('workspaceType', '==', 'rep_workspace')
    .where('ativo', '==', true)
    .limit(1)
    .get();

  let checkoutPlansResult = { status: 0, payload: {} };
  if (!repTenantSnapshot.empty) {
    const tenantId = repTenantSnapshot.docs[0].id;
    checkoutPlansResult = await fetchJson(
      LIST_STRIPE_CHECKOUT_PLANS_URL,
      { tenantId },
      idToken,
    );
  }

  console.log('--- VERIFY STRIPE PLANS ---');
  console.log('platformAdminUid:', platformAdminUid);
  console.log('listStripeCatalog status:', catalogResult.status);
  console.log(
    'listStripeCatalog products:',
    Array.isArray(catalogResult.payload.products)
      ? catalogResult.payload.products.length
      : 'n/a',
  );

  const catalogProducts = Array.isArray(catalogResult.payload.products)
    ? catalogResult.payload.products
    : [];
  console.log('all Stripe catalog products:');
  for (const product of catalogProducts) {
    const prices = Array.isArray(product.prices) ? product.prices : [];
    console.log(
      `  - ${product.productName} (${product.productId}) prices=${prices.length}`,
    );
    for (const price of prices) {
      console.log(
        `      price=${price.priceId} amount=${price.unitAmount} ${price.currency} interval=${price.recurringInterval}/${price.recurringIntervalCount} active=${price.active}`,
      );
    }
  }

  const representacoesProducts = catalogProducts.filter((product) =>
    normalizeText(product.productName).includes('representa'),
  );

  console.log('representacoes products in Stripe catalog:', representacoesProducts.length);
  for (const product of representacoesProducts) {
    const prices = Array.isArray(product.prices) ? product.prices : [];
    console.log(
      `  - ${product.productName} (${product.productId}) prices=${prices.length}`,
    );
    for (const price of prices) {
      console.log(
        `      price=${price.priceId} amount=${price.unitAmount} ${price.currency} interval=${price.recurringInterval}/${price.recurringIntervalCount} active=${price.active}`,
      );
    }
  }

  console.log('active plan_mappings total:', mappings.length);
  console.log('representacoes plan_mappings:', representacoesMappings.length);
  for (const item of representacoesMappings) {
    console.log(
      `  - key=${item.billingPlanKey} type=${item.mappingType} metric=${item.overageMetric ?? ''} includedSeats=${item.includedSeats ?? 0} seatAddonPlanKey=${item.seatAddonPlanKey ?? ''} linkedBasePlanKey=${item.linkedBasePlanKey ?? ''}`,
    );
  }

  let relationOk = false;
  if (representacoesBase.length > 0 && representacoesAddon.length > 0) {
    relationOk = representacoesBase.some((base) =>
      representacoesAddon.some(
        (addon) =>
          String(base.seatAddonPlanKey ?? '').toLowerCase() ===
            String(addon.billingPlanKey ?? '').toLowerCase() &&
          String(addon.linkedBasePlanKey ?? '').toLowerCase() ===
            String(base.billingPlanKey ?? '').toLowerCase(),
      ),
    );
  }

  console.log('representacoes base mappings:', representacoesBase.length);
  console.log('representacoes addon mappings (extra_usuario):', representacoesAddon.length);
  console.log('base + addon relation ok:', relationOk);

  console.log('listStripeCheckoutPlans status:', checkoutPlansResult.status);
  if (checkoutPlansResult.status === 200) {
    const plans = Array.isArray(checkoutPlansResult.payload.plans)
      ? checkoutPlansResult.payload.plans
      : [];
    console.log('checkout plans returned:', plans.length);
    for (const plan of plans) {
      console.log(
        `  - planKey=${plan.billingPlanKey} name=${plan.planDisplayName} seats=${plan.includedSeats ?? 0} addonKey=${plan.seatAddonPlanKey ?? ''}`,
      );
    }
  } else {
    console.log('checkout plans payload:', JSON.stringify(checkoutPlansResult.payload));
  }
}

main().catch((error) => {
  console.error('VERIFY_STRIPE_PLANS_ERROR', error?.message ?? error);
  process.exit(1);
});
