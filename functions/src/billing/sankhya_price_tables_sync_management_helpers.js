async function executeSyncSankhyaPriceTablesNightlyAction({
  firestore,
  authenticateInSankhya,
  readBearerToken,
  syncSankhyaPriceTablesModule,
  loggerError,
  loggerLog,
}) {
  const tenantsSnapshot = await firestore.collection('tenants').get();

  let processedTenants = 0;
  let skippedTenants = 0;
  let failedTenants = 0;

  for (const tenantDoc of tenantsSnapshot.docs) {
    const tenantId = tenantDoc.id;
    const tenantData = tenantDoc.data() || {};
    const integration =
      tenantData.erpIntegration && typeof tenantData.erpIntegration === 'object'
        ? tenantData.erpIntegration
        : {};
    const credentials =
      integration.credentials && typeof integration.credentials === 'object'
        ? integration.credentials
        : {};

    const provider = String(integration.provider ?? '').trim().toLowerCase();
    const environment = String(integration.environment ?? '')
      .trim()
      .toLowerCase();
    const clientId = String(credentials.username ?? '').trim();
    const clientSecret = String(credentials.password ?? '').trim();
    const xToken = String(credentials.accessToken ?? '').trim();

    if (
      provider !== 'sankhya' ||
      !['homolog', 'prod'].includes(environment) ||
      !clientId ||
      !clientSecret ||
      !xToken
    ) {
      skippedTenants += 1;
      continue;
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
        throw new Error('Autenticacao sem access_token.');
      }

      await syncSankhyaPriceTablesModule({
        firestore,
        tenantId,
        baseUrl,
        bearerToken,
        xToken,
      });
      processedTenants += 1;
    } catch (error) {
      failedTenants += 1;
      loggerError(
        '[syncSankhyaPriceTablesNightly] tenant_failed',
        JSON.stringify({
          tenantId,
          message: error instanceof Error ? error.message : String(error),
        }),
      );
    }
  }

  loggerLog(
    '[syncSankhyaPriceTablesNightly] summary',
    JSON.stringify({ processedTenants, skippedTenants, failedTenants }),
  );

  return {
    processedTenants,
    skippedTenants,
    failedTenants,
  };
}

module.exports = {
  executeSyncSankhyaPriceTablesNightlyAction,
};
