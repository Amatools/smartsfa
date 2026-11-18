async function executeSyncSankhyaClientesModuleAction({
  firestore,
  tenantId,
  baseUrl,
  bearerToken,
  xToken,
  codigosFiltro,
  buildSankhyaClientesSql,
  executeSankhyaDbExplorerQuery,
  buildClienteDocId,
  readRowValueByAliases,
  mapSankhyaClienteRow,
  lookupCepAddress,
  updateTenantSyncState,
  loggerError,
}) {
  const nowIso = new Date().toISOString();
  const syncBatchId = `sankhya_clientes_${Date.now()}`;
  const sql = buildSankhyaClientesSql({ codigosFiltro });
  const queryResult = await executeSankhyaDbExplorerQuery({
    baseUrl,
    bearerToken,
    xToken,
    sql,
  });

  const clientesCollection = firestore.collection('clientes');
  const writer = firestore.bulkWriter();
  writer.onWriteError((error) => {
    if (error.failedAttempts < 3) {
      return true;
    }
    loggerError(
      '[syncSankhyaClientesModule] write_failed',
      JSON.stringify({
        code: error.code,
        message: error.message,
        documentPath: error.documentRef?.path || null,
        failedAttempts: error.failedAttempts,
      }),
    );
    return false;
  });

  const syncVersionBase = Date.now() * 1000;
  let importedCount = 0;
  let skippedInvalidCount = 0;
  let prunedInactiveCount = 0;
  const cepCache = new Map();
  const mappedClienteIds = new Set();
  const isFullSync = !codigosFiltro || codigosFiltro.length === 0;

  try {
    for (let index = 0; index < queryResult.rows.length; index++) {
      const row = queryResult.rows[index];
      const docId = buildClienteDocId(
        tenantId,
        readRowValueByAliases(row, ['CODPARC']),
      );
      const ref = clientesCollection.doc(docId);
      const existingSnapshot = await ref.get();
      const existingData = existingSnapshot.exists
        ? existingSnapshot.data() || {}
        : {};

      const mapped = mapSankhyaClienteRow({
        tenantId,
        row,
        nowIso,
        syncBatchId,
        syncVersion: syncVersionBase + index,
        existingData,
      });

      if (!mapped) {
        skippedInvalidCount += 1;
        continue;
      }

      if (mapped.cep && !mapped.logradouro) {
        if (!cepCache.has(mapped.cep)) {
          cepCache.set(mapped.cep, await lookupCepAddress(mapped.cep));
        }
        const cepInfo = cepCache.get(mapped.cep);
        if (cepInfo) {
          mapped.logradouro = mapped.logradouro || cepInfo.logradouro;
          mapped.bairro = mapped.bairro || cepInfo.bairro;
        }
      }

      writer.set(ref, mapped, { merge: true });
      mappedClienteIds.add(docId);
      importedCount += 1;
    }

    if (isFullSync) {
      const existingErpSnapshot = await clientesCollection
        .where('tenantId', '==', tenantId)
        .where('origemCadastro', '==', 'erp')
        .get();
      for (const doc of existingErpSnapshot.docs) {
        if (mappedClienteIds.has(doc.id)) {
          continue;
        }
        const payload = doc.data() || {};
        if (payload.status === 'inativo') {
          continue;
        }
        writer.set(
          doc.ref,
          { status: 'inativo', updatedAt: nowIso },
          { merge: true },
        );
        prunedInactiveCount += 1;
      }
    }
  } finally {
    await writer.close();
  }

  await updateTenantSyncState({
    firestore,
    tenantId,
    patch: {
      lastClientesSyncAt: nowIso,
      lastClientesSyncMode: codigosFiltro?.length ? 'test_filtered' : 'full',
      lastClientesSourceCount: queryResult.rows.length,
      lastClientesImportedCount: importedCount,
      lastClientesSkippedInvalidCount: skippedInvalidCount,
      lastClientesPrunedInactiveCount: prunedInactiveCount,
      lastClientesEndpoint: queryResult.endpointPath,
    },
  });

  return {
    message: codigosFiltro?.length
      ? `Sincronizacao de teste de clientes concluida (restrita aos codigos: ${codigosFiltro.join(', ')}).`
      : 'Sincronizacao completa de clientes concluida via SQL DbExplorer.',
    endpoint: queryResult.endpointPath,
    sourceCount: queryResult.rows.length,
    importedCount,
    skippedInvalidCount,
    prunedInactiveCount,
    codigosFiltro: codigosFiltro ?? [],
  };
}

module.exports = {
  executeSyncSankhyaClientesModuleAction,
};
