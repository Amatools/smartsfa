async function executeFetchSankhyaOperationTypesAction({
  requestBody,
  authenticateInSankhya,
  readBearerToken,
  buildSankhyaOperationTypesSql,
  executeSankhyaDbExplorerQuery,
  mapSankhyaOperationTypeRow,
}) {
  const environment = String(requestBody?.environment ?? '')
    .trim()
    .toLowerCase();
  const clientId = String(requestBody?.clientId ?? '').trim();
  const clientSecret = String(requestBody?.clientSecret ?? '').trim();
  const xToken = String(requestBody?.xToken ?? '').trim();

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

    const sql = buildSankhyaOperationTypesSql();
    const queryResult = await executeSankhyaDbExplorerQuery({
      baseUrl,
      bearerToken,
      xToken,
      sql,
    });

    const operationTypes = queryResult.rows
      .map((row) => mapSankhyaOperationTypeRow(row))
      .filter((item) => item && item.code);

    return {
      status: 200,
      body: {
        ok: true,
        environment,
        endpoint: queryResult.endpointPath,
        rowCount: operationTypes.length,
        operationTypes,
      },
    };
  } catch (error) {
    return {
      status: 502,
      body: {
        error: 'sankhya_operation_types_failed',
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }
}

module.exports = {
  executeFetchSankhyaOperationTypesAction,
};
