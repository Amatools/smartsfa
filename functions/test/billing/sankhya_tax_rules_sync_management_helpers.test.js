const test = require('node:test');
const assert = require('node:assert/strict');

const {
  executeSyncSankhyaTaxRulesModuleAction,
} = require('../../src/billing/sankhya_tax_rules_sync_management_helpers');

function createRef(path, store) {
  return {
    path,
    async get() {
      const value = store.get(path);
      if (!value) {
        return { exists: false, data: () => undefined };
      }
      return { exists: true, data: () => value };
    },
  };
}

function createFirestoreHarness({ existingRuleDocs = [], existingGroupDocs = {} } = {}) {
  const sets = [];
  const deletes = [];
  const store = new Map();

  const taxRulesDocs = existingRuleDocs.map((doc) => ({
    id: doc.id,
    ref: createRef(`tax_rules/${doc.id}`, store),
    data: () => doc,
  }));

  const collections = {
    tax_rules: {
      doc(id) {
        return createRef(`tax_rules/${id}`, store);
      },
      where() {
        return {
          async get() {
            return { docs: taxRulesDocs };
          },
        };
      },
    },
    tax_rule_groups: {
      doc(id) {
        const path = `tax_rule_groups/${id}`;
        const existing = existingGroupDocs[id];
        return {
          path,
          async get() {
            if (!existing) {
              return { exists: false, data: () => undefined };
            }
            return { exists: true, data: () => existing };
          },
        };
      },
    },
  };

  const writer = {
    onWriteError() {},
    set(ref, payload) {
      sets.push({ path: ref.path, payload });
      store.set(ref.path, payload);
    },
    delete(ref) {
      deletes.push(ref.path);
      store.delete(ref.path);
    },
    async close() {},
  };

  const firestore = {
    collection(name) {
      return collections[name];
    },
    bulkWriter() {
      return writer;
    },
  };

  return {
    firestore,
    sets,
    deletes,
  };
}

test('executeSyncSankhyaTaxRulesModuleAction groups NCMs and prunes stale ERP rules', async () => {
  const harness = createFirestoreHarness({
    existingRuleDocs: [
      {
        id: 'stale_erp_rule',
        tenantId: 't1',
        origin: 'erp',
        representedCompanyId: null,
      },
      {
        id: 'manual_rule',
        tenantId: 't1',
        origin: 'manual',
      },
    ],
  });

  const syncPatches = [];

  const rows = [{ key: 'n1' }, { key: 'n2' }, { key: 'generic' }, { key: 'invalid' }];
  const mappedByKey = {
    n1: {
      id: 'rule_n1_any_any',
      tenantId: 't1',
      origin: 'erp',
      ncm: '10010010',
      ufOrigem: 'SP',
      ufDestino: 'RJ',
      cest: null,
    },
    n2: {
      id: 'rule_n2_any_any',
      tenantId: 't1',
      origin: 'erp',
      ncm: '10010020',
      ufOrigem: 'SP',
      ufDestino: 'RJ',
      cest: '123',
    },
    generic: {
      id: 'rule_generic_any_any',
      tenantId: 't1',
      origin: 'erp',
      ncm: null,
      ufOrigem: 'ANY',
      ufDestino: 'ANY',
      cest: null,
    },
  };

  const result = await executeSyncSankhyaTaxRulesModuleAction({
    firestore: harness.firestore,
    tenantId: 't1',
    baseUrl: 'https://base',
    bearerToken: 'bt',
    xToken: 'xt',
    buildSankhyaTaxRulesSql: () => 'SELECT 1',
    executeSankhyaDbExplorerQuery: async () => ({
      rows,
      endpointPath: '/dbexplorer',
    }),
    mapSankhyaTaxRuleRow: ({ row }) => mappedByKey[row.key] || null,
    normalizeDigits: (value) => (value ? String(value).replace(/\D+/g, '') : null),
    computeFingerprintHash: () => 'hash_same',
    buildTaxFingerprintKey: () => 'fingerprint',
    sanitizeKeyToken: (value, fallback) => String(value || fallback).toLowerCase(),
    buildAutoGroupName: () => 'Auto Group',
    buildAutoGroupDescription: () => 'Auto Description',
    applyTaxGroupsToExistingProducts: async ({ ncmToGroupId }) => ncmToGroupId.size,
    updateTenantSyncState: async ({ patch }) => {
      syncPatches.push(patch);
    },
    loggerError: () => {},
  });

  assert.equal(result.sourceCount, 4);
  assert.equal(result.skippedInvalidCount, 1);
  assert.equal(result.groupsCreatedCount, 1);
  assert.equal(result.groupedNcmCount, 2);
  assert.equal(result.productsGroupLinkedCount, 2);
  assert.equal(result.prunedStaleRuleCount, 1);

  const upsertedGroup = harness.sets.find((entry) =>
    entry.path.startsWith('tax_rule_groups/erp_group_t1_hash_same'),
  );
  assert.ok(upsertedGroup);
  assert.deepEqual(upsertedGroup.payload.memberNcms, ['10010010', '10010020']);

  assert.ok(harness.deletes.includes('tax_rules/stale_erp_rule'));
  assert.ok(!harness.deletes.includes('tax_rules/manual_rule'));

  assert.equal(syncPatches.length, 1);
  assert.equal(syncPatches[0].lastTaxRulesSourceCount, 4);
  assert.equal(syncPatches[0].lastTaxRulesGroupsCreatedCount, 1);
});

test('executeSyncSankhyaTaxRulesModuleAction keeps ungrouped NCM rules when no cluster', async () => {
  const harness = createFirestoreHarness();

  const result = await executeSyncSankhyaTaxRulesModuleAction({
    firestore: harness.firestore,
    tenantId: 't1',
    baseUrl: 'https://base',
    bearerToken: 'bt',
    xToken: 'xt',
    buildSankhyaTaxRulesSql: () => 'SELECT 1',
    executeSankhyaDbExplorerQuery: async () => ({
      rows: [{ key: 'only_one_ncm' }],
      endpointPath: '/dbexplorer',
    }),
    mapSankhyaTaxRuleRow: () => ({
      id: 'rule_single_ncm',
      tenantId: 't1',
      origin: 'erp',
      ncm: '22030000',
      ufOrigem: 'SP',
      ufDestino: 'MG',
      cest: 'c1',
    }),
    normalizeDigits: (value) => value,
    computeFingerprintHash: () => 'hash_single',
    buildTaxFingerprintKey: () => 'fp_single',
    sanitizeKeyToken: (value, fallback) => String(value || fallback).toLowerCase(),
    buildAutoGroupName: () => 'name',
    buildAutoGroupDescription: () => 'desc',
    applyTaxGroupsToExistingProducts: async () => 0,
    updateTenantSyncState: async () => {},
    loggerError: () => {},
  });

  assert.equal(result.groupsCreatedCount, 0);
  assert.equal(result.groupedNcmCount, 0);
  assert.equal(result.productsGroupLinkedCount, 0);

  const wroteSingleRule = harness.sets.some(
    (entry) => entry.path === 'tax_rules/rule_single_ncm',
  );
  assert.ok(wroteSingleRule);
});
