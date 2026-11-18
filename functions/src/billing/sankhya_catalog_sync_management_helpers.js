async function executeSyncSankhyaCatalogModuleAction({
  firestore,
  request,
  requestBody,
  validateEnterpriseOwnerAccess,
  authenticateInSankhya,
  readBearerToken,
  syncSankhyaProductsModule,
  syncSankhyaTaxRulesModule,
  syncSankhyaClientesModule,
  syncSankhyaProductImagesModule,
  syncSankhyaPriceTablesModule,
}) {
  const tenantId = String(requestBody?.tenantId ?? '').trim();
  const moduleId = String(requestBody?.module ?? '').trim().toLowerCase();
  const environment = String(requestBody?.environment ?? '')
    .trim()
    .toLowerCase();
  const clientId = String(requestBody?.clientId ?? '').trim();
  const clientSecret = String(requestBody?.clientSecret ?? '').trim();
  const xToken = String(requestBody?.xToken ?? '').trim();
  const codigosFiltroRaw = requestBody?.codigosFiltro;
  const codigosFiltro = Array.isArray(codigosFiltroRaw)
    ? codigosFiltroRaw
    : [];

  if (!tenantId) {
    return {
      status: 400,
      body: {
        error: 'missing_tenant',
        message: 'tenantId e obrigatorio.',
      },
    };
  }

  if (!['homolog', 'prod'].includes(environment)) {
    return {
      status: 400,
      body: {
        error: 'invalid_environment',
        message: 'Use homolog ou prod.',
      },
    };
  }

  if (!clientId || !clientSecret || !xToken) {
    return {
      status: 400,
      body: {
        error: 'missing_credentials',
        message: 'Client Id, Client Secret e X-Token sao obrigatorios.',
      },
    };
  }

  if (!['produtos', 'tabelas_preco', 'tax_rules', 'clientes', 'product_images'].includes(moduleId)) {
    return {
      status: 400,
      body: {
        error: 'module_not_enabled',
        message:
          'Modulo ainda nao habilitado para ingestao. Valide endpoint/permissao e ative o modulo.',
        module: moduleId,
      },
    };
  }

  const accessValidation = await validateEnterpriseOwnerAccess({
    firestore,
    request,
    tenantId,
  });
  if (!accessValidation.allowed) {
    return {
      status: accessValidation.status,
      body: {
        error: accessValidation.error,
        message: accessValidation.message,
      },
    };
  }

  const baseUrl =
    environment === 'prod'
      ? 'https://api.sankhya.com.br'
      : 'https://api.sandbox.sankhya.com.br';

  try {
    const authPayload = await authenticateInSankhya({
      baseUrl,
      clientId,
      clientSecret,
      xToken,
    });

    const bearerToken = readBearerToken(authPayload);
    if (!bearerToken) {
      return {
        status: 502,
        body: {
          error: 'missing_bearer',
          message:
            'Autenticacao retornou sem access_token. Verifique credenciais e permissao do app Sankhya.',
        },
      };
    }

    let result;
    if (moduleId === 'produtos') {
      result = await syncSankhyaProductsModule({
        firestore,
        tenantId,
        baseUrl,
        bearerToken,
        xToken,
      });
    } else if (moduleId === 'tax_rules') {
      result = await syncSankhyaTaxRulesModule({
        firestore,
        tenantId,
        baseUrl,
        bearerToken,
        xToken,
      });
    } else if (moduleId === 'clientes') {
      result = await syncSankhyaClientesModule({
        firestore,
        tenantId,
        baseUrl,
        bearerToken,
        xToken,
        codigosFiltro,
      });
    } else if (moduleId === 'product_images') {
      result = await syncSankhyaProductImagesModule({
        firestore,
        tenantId,
        baseUrl,
        bearerToken,
        xToken,
      });
    } else {
      result = await syncSankhyaPriceTablesModule({
        firestore,
        tenantId,
        baseUrl,
        bearerToken,
        xToken,
      });
    }

    return {
      status: 200,
      body: {
        success: true,
        module: moduleId,
        environment,
        ...result,
      },
    };
  } catch (error) {
    return {
      status: 502,
      body: {
        error: 'sankhya_sync_failed',
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }
}

module.exports = {
  executeSyncSankhyaCatalogModuleAction,
};
