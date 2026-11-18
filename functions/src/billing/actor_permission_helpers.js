const {
  loadTenantMembershipByTenantAndUser,
} = require('./tenant_membership_helpers');

async function assertPlatformAdminActor({ firestore, uid }) {
  const normalizedUid = String(uid ?? '').trim();
  if (!normalizedUid) {
    return {
      allowed: false,
      status: 401,
      error: 'missing_uid',
      message: 'Usuario autenticado sem UID valido.',
      userData: null,
    };
  }

  const userDoc = await firestore.collection('usuarios').doc(normalizedUid).get();
  if (!userDoc.exists) {
    return {
      allowed: false,
      status: 403,
      error: 'user_not_found',
      message: 'Usuario autenticado nao encontrado em usuarios/{uid}.',
      userData: null,
    };
  }

  const userData = userDoc.data() || {};
  const platformRole = String(userData.platformRole ?? '').trim().toLowerCase();
  const activeGlobal = userData.ativoGlobal !== false;
  const consoleEnabled = userData.maintainerConsoleEnabled !== false;

  if (platformRole !== 'platform_admin' || !activeGlobal || !consoleEnabled) {
    return {
      allowed: false,
      status: 403,
      error: 'forbidden',
      message: 'Apenas platform_admin ativo com console habilitado pode operar billing Stripe.',
      userData,
    };
  }

  return {
    allowed: true,
    status: 200,
    error: '',
    message: '',
    userData,
  };
}

async function assertTenantBillingActorPermission({ firestore, uid, tenantId }) {
  const platformAccess = await assertPlatformAdminActor({ firestore, uid });
  if (platformAccess.allowed) {
    return {
      allowed: true,
      status: 200,
      error: '',
      message: '',
    };
  }

  const membership = await loadTenantMembershipByTenantAndUser({
    firestore,
    tenantId,
    uid,
  });

  if (!membership) {
    return {
      allowed: false,
      status: 403,
      error: 'membership_not_found',
      message: 'Usuario sem membership ativa no tenant informado.',
    };
  }

  const role = String(membership.role ?? '').trim().toLowerCase();
  const state = String(membership.state ?? 'active').trim().toLowerCase();
  const active = membership.ativo !== false;
  if (!active || state !== 'active' || role !== 'owner') {
    return {
      allowed: false,
      status: 403,
      error: 'owner_required',
      message: 'Somente owner ativo (ou platform_admin) pode operar checkout/billing do tenant.',
    };
  }

  return {
    allowed: true,
    status: 200,
    error: '',
    message: '',
  };
}

module.exports = {
  assertPlatformAdminActor,
  assertTenantBillingActorPermission,
};
