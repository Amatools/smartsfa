function toCodeStringFallback(value) {
  if (value === null || value === undefined) {
    return '';
  }

  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      return '';
    }
    return String(Math.trunc(value));
  }

  return String(value).trim();
}

function buildProductDocId(tenantId, productCode) {
  return `erp_prod_${tenantId}_${toCodeStringFallback(productCode)}`;
}

function mapSankhyaProductToFirestore({
  tenantId,
  nowIso,
  syncBatchId,
  internalCode,
  source,
  productFiscal,
  existingData,
  nextSyncVersion,
  ncmToGroupId,
  normalizeOrigemMercadoriaCst,
  toNumberOrNull,
  normalizeDigits,
  buildProductDocId,
}) {
  const toCodeString = toCodeStringFallback;
  const code = toCodeString(source.codigoProduto);
  const name = String(source.nome ?? '').trim();
  const groupName = String(source.nomeGrupoProduto ?? '').trim();
  const volume = String(source.volume ?? '').trim();
  const brand = String(source.marca ?? '').trim();
  const ncmRaw = String(source.ncm ?? '').trim();
  const cestRaw = String(source.cest ?? '').trim();
  const eanRaw = String(source.referencia ?? '').trim();
  const origemMercadoriaCst = normalizeOrigemMercadoriaCst(
    productFiscal?.origemMercadoriaCst ?? existingData.origemMercadoriaCst,
  );
  const aliquotaIpiBase = toNumberOrNull(
    productFiscal?.aliquotaIpiBase ?? existingData.aliquotaIpiBase,
  );
  const ncmDigits = normalizeDigits(ncmRaw);
  const grupoTributarioId =
    (ncmDigits ? ncmToGroupId?.get(ncmDigits) : null) ??
    existingData.grupoTributarioId ??
    null;

  return {
    id: buildProductDocId(tenantId, code),
    tenantId,
    representedCompanyId: existingData.representedCompanyId ?? null,
    codigoInterno: internalCode,
    descricao: name || `Produto ${code}`,
    descricaoResumida: name || null,
    descricaoLonga: String(source.complemento ?? '').trim() || null,
    codigoFabricante: code,
    ean: eanRaw || null,
    marca: brand || null,
    categoria: groupName || null,
    unidade: volume || null,
    ncm: ncmRaw || null,
    cest: cestRaw || null,
    grupoTributarioId,
    origemMercadoriaCst,
    aliquotaIpiBase,
    pesoKg: toNumberOrNull(source.pesoBruto),
    larguraMm: toNumberOrNull(source.largura),
    alturaMm: toNumberOrNull(source.altura),
    comprimentoMm: toNumberOrNull(source.espessura),
    origemCadastro: 'erp',
    status: source.ativo === false ? 'inativo' : 'ativo',
    erpProductId: code,
    erpSyncId: syncBatchId,
    updatedAt: nowIso,
    createdAt: existingData.createdAt || nowIso,
    deletedAt: null,
    syncVersion: nextSyncVersion,
  };
}

async function resolveInternalProductCode({
  firestore,
  tenantId,
  erpProductCode,
  existingData,
  nextTenantErpProductInternalSequence,
}) {
  const currentInternalCode = String(existingData.codigoInterno ?? '').trim();
  if (currentInternalCode && currentInternalCode !== erpProductCode) {
    return currentInternalCode;
  }

  const sequence = await nextTenantErpProductInternalSequence({
    firestore,
    tenantId,
  });
  return `ERP-${String(sequence).padStart(6, '0')}`;
}

async function nextTenantErpProductInternalSequence({
  firestore,
  tenantId,
  readInt,
  admin,
}) {
  const tenantRef = firestore.collection('tenants').doc(tenantId);
  return firestore.runTransaction(async (transaction) => {
    const tenantSnapshot = await transaction.get(tenantRef);
    const current = readInt(tenantSnapshot.data()?.erpInternalProductSequence);
    const next = current + 1;
    transaction.set(
      tenantRef,
      {
        erpInternalProductSequence: next,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return next;
  });
}

module.exports = {
  mapSankhyaProductToFirestore,
  resolveInternalProductCode,
  nextTenantErpProductInternalSequence,
  buildProductDocId,
};
