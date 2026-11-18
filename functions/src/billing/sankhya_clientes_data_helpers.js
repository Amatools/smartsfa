function toCodeString(value) {
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

function isZeroCode(codeValue) {
  const normalized = String(codeValue ?? '').trim();
  if (!normalized) {
    return true;
  }

  const numeric = Number(normalized.replace(',', '.'));
  if (Number.isFinite(numeric) && numeric === 0) {
    return true;
  }

  return /^0+$/.test(normalized);
}

function normalizeDigits(value) {
  const token = String(value ?? '').trim();
  if (!token) {
    return '';
  }
  return token.replace(/[^0-9]/g, '');
}

function nullableString(value) {
  const token = String(value ?? '').trim();
  return token ? token : null;
}

function normalizeSankhyaNumericCodeList(values) {
  const seen = new Set();
  const normalized = [];

  for (const item of values || []) {
    const token = String(item ?? '').trim();
    if (!token) {
      continue;
    }
    if (!/^\d+$/.test(token)) {
      continue;
    }
    if (isZeroCode(token)) {
      continue;
    }
    const clean = String(Number.parseInt(token, 10));
    if (!clean || seen.has(clean)) {
      continue;
    }
    seen.add(clean);
    normalized.push(clean);
  }

  return normalized;
}

function readRowValueByAliases(row, aliases) {
  if (!row || typeof row !== 'object') {
    return undefined;
  }

  for (const alias of aliases) {
    if (Object.prototype.hasOwnProperty.call(row, alias)) {
      return row[alias];
    }
  }

  const loweredMap = new Map(
    Object.entries(row).map(([key, value]) => [key.toLowerCase(), value]),
  );
  for (const alias of aliases) {
    const value = loweredMap.get(String(alias).toLowerCase());
    if (value !== undefined) {
      return value;
    }
  }

  return undefined;
}

function buildClienteDocId(tenantId, codigoParceiro) {
  return `erp_cliente_${tenantId}_${toCodeString(codigoParceiro)}`;
}

const SANKHYA_DEFAULT_TAX_REGIME = 'simples_nacional';
const SANKHYA_CLASSIFICMS_CONTRIBUINTE_CODES = new Set(['R', 'P', 'X']);
const SANKHYA_CLASSIFICMS_NAO_CONTRIBUINTE_CODES = new Set(['C', 'I', 'N']);

function buildSankhyaClientesSql({ codigosFiltro } = {}) {
  const safeCodes = normalizeSankhyaNumericCodeList(codigosFiltro ?? []);
  const filtroCodigo =
    safeCodes.length > 0 ? `\n  AND PAR.CODPARC IN (${safeCodes.join(', ')})` : '';

  return `
SELECT
    TO_CHAR(PAR.CODPARC) AS CODPARC,
    PAR.NOMEPARC,
    PAR.RAZAOSOCIAL,
    PAR.CGC_CPF,
    PAR.TIPPESSOA,
    PAR.ATIVO,
    PAR.IDENTINSCESTAD,
    PAR.INSCMUN,
    PAR.CLASSIFICMS,
    PAR.CEP,
    PAR.NUMEND,
    PAR.COMPLEMENTO,
    PAR.TELEFONE,
    PAR.EMAIL,
    CID.NOMECID,
    UFS.UF AS SIGLA_UF
FROM TGFPAR PAR
LEFT JOIN TSICID CID ON CID.CODCID = PAR.CODCID
LEFT JOIN TSIUFS UFS ON UFS.CODUF = CID.UF
WHERE PAR.CLIENTE = 'S'${filtroCodigo}
`;
}

function mapSankhyaClienteRow({
  tenantId,
  row,
  nowIso,
  syncBatchId,
  syncVersion,
  existingData,
}) {
  const existing = existingData || {};
  const codigo = toCodeString(readRowValueByAliases(row, ['CODPARC']));
  if (!codigo || isZeroCode(codigo)) {
    return null;
  }

  const razaoSocial = String(
    readRowValueByAliases(row, ['RAZAOSOCIAL']) ?? '',
  ).trim();
  const nomeFantasia = String(
    readRowValueByAliases(row, ['NOMEPARC']) ?? '',
  ).trim();
  const documento = normalizeDigits(readRowValueByAliases(row, ['CGC_CPF']));
  const tipPessoaRaw = String(readRowValueByAliases(row, ['TIPPESSOA']) ?? '')
    .trim()
    .toUpperCase();
  const ativoRaw = String(readRowValueByAliases(row, ['ATIVO']) ?? '')
    .trim()
    .toUpperCase();
  const inscricaoEstadualRaw = String(
    readRowValueByAliases(row, ['IDENTINSCESTAD']) ?? '',
  ).trim();
  const classificmsRaw =
    nullableString(readRowValueByAliases(row, ['CLASSIFICMS']))?.toUpperCase() ??
    null;
  const inscricaoEstadualUpper = inscricaoEstadualRaw.toUpperCase();
  const hasValidIe =
    inscricaoEstadualUpper.length > 0 && inscricaoEstadualUpper !== 'ISENTO';

  let taxProfile;
  if (SANKHYA_CLASSIFICMS_CONTRIBUINTE_CODES.has(classificmsRaw)) {
    taxProfile = 'contribuinte';
  } else if (SANKHYA_CLASSIFICMS_NAO_CONTRIBUINTE_CODES.has(classificmsRaw)) {
    taxProfile = 'nao_contribuinte';
  } else {
    taxProfile = hasValidIe ? 'contribuinte' : 'nao_contribuinte';
  }

  let salePurposeFromClassificms = null;
  if (classificmsRaw === 'R') {
    salePurposeFromClassificms = 'revenda';
  } else if (
    classificmsRaw === 'C' ||
    classificmsRaw === 'N' ||
    classificmsRaw === 'X'
  ) {
    salePurposeFromClassificms = 'uso_consumo';
  }

  return {
    id: buildClienteDocId(tenantId, codigo),
    tenantId,
    representedCompanyId: existing.representedCompanyId ?? null,
    ownerId: existing.ownerId ?? null,
    gerenteId: existing.gerenteId ?? null,
    representanteId: existing.representanteId ?? null,
    vendedorId: existing.vendedorId ?? null,
    nome: razaoSocial || nomeFantasia || `Cliente ${codigo}`,
    nomeFantasia: nullableString(nomeFantasia),
    documento: nullableString(documento),
    tipoPessoa: tipPessoaRaw === 'F' ? 'pf' : 'pj',
    cep: nullableString(normalizeDigits(readRowValueByAliases(row, ['CEP']))),
    numero: nullableString(readRowValueByAliases(row, ['NUMEND'])),
    complemento: nullableString(readRowValueByAliases(row, ['COMPLEMENTO'])),
    cidade: nullableString(readRowValueByAliases(row, ['NOMECID'])),
    estado: nullableString(
      String(readRowValueByAliases(row, ['SIGLA_UF']) ?? '')
        .trim()
        .toUpperCase(),
    ),
    logradouro: existing.logradouro ?? null,
    bairro: existing.bairro ?? null,
    telefone: nullableString(readRowValueByAliases(row, ['TELEFONE'])),
    email: nullableString(readRowValueByAliases(row, ['EMAIL'])),
    inscricaoEstadual: nullableString(inscricaoEstadualRaw),
    inscricaoMunicipal: nullableString(
      readRowValueByAliases(row, ['INSCMUN']),
    ),
    taxProfile,
    taxRegime: existing.taxRegime || SANKHYA_DEFAULT_TAX_REGIME,
    isZfmSuframa: existing.isZfmSuframa ?? false,
    salePurpose: salePurposeFromClassificms || existing.salePurpose || 'revenda',
    origemCadastro: 'erp',
    status: ativoRaw === 'S' ? 'aprovado' : 'inativo',
    erpClassificmsRaw: classificmsRaw,
    erpSyncId: syncBatchId,
    createdAt: existing.createdAt || nowIso,
    updatedAt: nowIso,
    deletedAt: null,
    syncVersion,
  };
}

async function lookupCepAddress(
  cep,
  {
    fetchImpl = fetch,
    loggerError = () => {},
  } = {},
) {
  try {
    const response = await fetchImpl(`https://brasilapi.com.br/api/cep/v2/${cep}`);
    if (!response.ok) {
      return null;
    }
    const data = await response.json();
    return {
      logradouro: nullableString(data?.street),
      bairro: nullableString(data?.neighborhood),
    };
  } catch (error) {
    loggerError(
      '[lookupCepAddress] failed',
      JSON.stringify({ cep, message: error?.message }),
    );
    return null;
  }
}

module.exports = {
  buildClienteDocId,
  buildSankhyaClientesSql,
  mapSankhyaClienteRow,
  lookupCepAddress,
};
