async function executeValidateEnterpriseOwnerAccess({
  firestore,
  request,
  tenantId,
  verifyIdToken,
  loadTenantMembershipByTenantAndUser,
}) {
  const authHeader = String(request.headers?.authorization ?? '').trim();
  if (!authHeader.toLowerCase().startsWith('bearer ')) {
    return {
      allowed: false,
      status: 401,
      error: 'missing_firebase_auth',
      message: 'Envie Authorization: Bearer <Firebase ID token>.',
    };
  }

  const idToken = authHeader.substring(7).trim();
  if (!idToken) {
    return {
      allowed: false,
      status: 401,
      error: 'invalid_firebase_auth',
      message: 'Token Firebase invalido ou ausente.',
    };
  }

  let decodedToken;
  try {
    decodedToken = await verifyIdToken(idToken);
  } catch (_) {
    return {
      allowed: false,
      status: 401,
      error: 'firebase_auth_failed',
      message: 'Falha ao validar autenticacao Firebase para sync ERP.',
    };
  }

  const uid = String(decodedToken?.uid ?? '').trim();
  if (!uid) {
    return {
      allowed: false,
      status: 401,
      error: 'missing_uid',
      message: 'Usuario autenticado sem UID valido.',
    };
  }

  const tenantDoc = await firestore.collection('tenants').doc(tenantId).get();
  if (!tenantDoc.exists) {
    return {
      allowed: false,
      status: 404,
      error: 'tenant_not_found',
      message: 'Tenant nao encontrado para o sync ERP.',
    };
  }

  const tenantData = tenantDoc.data() || {};
  const workspaceType = String(tenantData.workspaceType ?? '').trim();
  if (workspaceType !== 'brand_owner_workspace') {
    return {
      allowed: false,
      status: 403,
      error: 'workspace_not_allowed',
      message:
        'Sincronizacao ERP permitida apenas para contas enterprise (brand_owner_workspace).',
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
      message: 'Usuario sem membership ativa neste tenant.',
    };
  }

  const role = String(membership.role ?? '').trim().toLowerCase();
  const state = String(membership.state ?? 'active').trim().toLowerCase();
  const ativo = membership.ativo !== false;

  if (role !== 'owner' || !ativo || state !== 'active') {
    return {
      allowed: false,
      status: 403,
      error: 'owner_required',
      message:
        'Somente owner ativo do tenant enterprise pode configurar e executar sync ERP.',
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
  executeValidateEnterpriseOwnerAccess,
};
