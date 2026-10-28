import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/core/models/domain_types.dart';
import 'package:smartsfa/src/core/models/product_base_price.dart';
import 'package:smartsfa/src/core/models/produto.dart';
import 'package:smartsfa/src/core/models/tax_operation_profile.dart';
import 'package:smartsfa/src/core/models/tax_rule.dart';
import 'package:smartsfa/src/core/repositories/product_base_price_repository.dart';
import 'package:smartsfa/src/core/repositories/produto_repository.dart';
import 'package:smartsfa/src/core/repositories/tax_operation_profile_repository.dart';
import 'package:smartsfa/src/core/repositories/tax_rule_repository.dart';
import 'package:smartsfa/src/features/precos/services/product_tax_engine_service.dart';

void main() {
  group('ProductTaxEngineService uso/consumo tax profile', () {
    const tenantId = 'tenant-1';
    const representedCompanyId = 'rep-1';
    const produtoId = 'prod-1';
    const tabelaId = 'tab-1';

    late ProductTaxEngineService service;

    setUp(() {
      final produtoRepo = _FakeProdutoRepository(
        items: <Produto>[
          const Produto(
            id: produtoId,
            tenantId: tenantId,
            codigoInterno: 'P-001',
            descricao: 'Produto teste',
            origemCadastro: ProductSource.manual,
            status: ProductStatus.active,
            grupoTributarioId: 'grp-1',
            ncm: '84212300',
            cest: '0100100',
            aliquotaIpiBase: 0,
          ),
        ],
      );

      final basePriceRepo = _FakeProductBasePriceRepository(
        items: <ProductBasePrice>[
          const ProductBasePrice(
            id: 'pbp-1',
            tenantId: tenantId,
            productId: produtoId,
            priceTableId: tabelaId,
            regionId: 'SP',
            basePrice: 100,
            status: 'active',
          ),
        ],
      );

      final taxRuleRepo = _FakeTaxRuleRepository(
        items: <TaxRule>[
          const TaxRule(
            id: 'rule-1',
            tenantId: tenantId,
            representedCompanyId: representedCompanyId,
            status: 'active',
            ufOrigem: 'SP',
            ufDestino: 'SP',
            ncm: '84212300',
            stCalculationType: 'mva',
            mvaIva: 40,
            aliquotaCredito: 12,
            aliquotaDestino: 18,
            aliquotaDifal: 5,
            priority: 10,
          ),
        ],
      );

      service = ProductTaxEngineService(
        produtoRepository: produtoRepo,
        basePriceRepository: basePriceRepo,
        taxRuleRepository: taxRuleRepo,
      );
    });

    test('suppresses ST and DIFAL for contribuinte on uso/consumo same UF', () async {
      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        salePurpose: SalePurpose.usoConsumo,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        representedCompanyId: representedCompanyId,
        ufOrigem: 'SP',
      );

      expect(result.precoBase, 100);
      expect(result.valorSt, 0);
      expect(result.valorDifal, 0);
      expect(result.valorTotalItem, closeTo(100, 0.0001));
      expect(result.operationProfileKey, 'uso_consumo_contribuinte_same_uf');
    });

    test('suppresses ST and DIFAL for nao contribuinte on uso/consumo same UF', () async {
      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        salePurpose: SalePurpose.usoConsumo,
        customerTaxProfile: CustomerTaxProfile.naoContribuinte,
        representedCompanyId: representedCompanyId,
        ufOrigem: 'SP',
      );

      expect(result.precoBase, 100);
      expect(result.valorSt, 0);
      expect(result.valorDifal, 0);
      expect(result.valorTotalItem, closeTo(100, 0.0001));
      expect(result.operationProfileKey, 'uso_consumo_nao_contribuinte_same_uf');
    });

    test('applies ZFM discount on product value and suppresses ST/DIFAL', () async {
      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        salePurpose: SalePurpose.usoConsumo,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        isZonaFrancaSuframa: true,
        representedCompanyId: representedCompanyId,
        ufOrigem: 'SP',
      );

      // For ZFM, we apply aliquotaDestino discount (18%) over product value.
      expect(result.precoBase, closeTo(82, 0.0001));
      expect(result.valorSt, 0);
      expect(result.valorDifal, 0);
      expect(result.valorTotalItem, closeTo(82, 0.0001));
      expect(result.operationProfileKey, 'zfm_comercializacao_revenda');
    });

    test('keeps ZFM total at zero when discount rate would exceed item base', () async {
      final localService = ProductTaxEngineService(
        produtoRepository: _FakeProdutoRepository(
          items: const <Produto>[
            Produto(
              id: produtoId,
              tenantId: tenantId,
              codigoInterno: 'P-001',
              descricao: 'Produto teste',
              origemCadastro: ProductSource.manual,
              status: ProductStatus.active,
              ncm: '84212300',
              cest: '0100100',
              aliquotaIpiBase: 0,
            ),
          ],
        ),
        basePriceRepository: _FakeProductBasePriceRepository(
          items: const <ProductBasePrice>[
            ProductBasePrice(
              id: 'pbp-1',
              tenantId: tenantId,
              productId: produtoId,
              priceTableId: tabelaId,
              regionId: 'SP',
              basePrice: 100,
              status: 'active',
            ),
          ],
        ),
        taxRuleRepository: _FakeTaxRuleRepository(
          items: const <TaxRule>[
            TaxRule(
              id: 'rule-zfm-high',
              tenantId: tenantId,
              representedCompanyId: representedCompanyId,
              status: 'active',
              ufOrigem: 'SP',
              ufDestino: 'SP',
              ncm: '84212300',
              aliquotaDestino: 120,
              aliquotaCredito: 12,
              aliquotaDifal: 5,
              priority: 20,
            ),
          ],
        ),
      );

      final result = await localService.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        salePurpose: SalePurpose.revenda,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        isZonaFrancaSuframa: true,
        representedCompanyId: representedCompanyId,
        ufOrigem: 'SP',
      );

      expect(result.precoBase, 0);
      expect(result.valorSt, 0);
      expect(result.valorDifal, 0);
      expect(result.valorTotalItem, 0);
    });

    test('falls back to global rule when represented-specific rule is absent', () async {
      final localService = ProductTaxEngineService(
        produtoRepository: _FakeProdutoRepository(
          items: const <Produto>[
            Produto(
              id: produtoId,
              tenantId: tenantId,
              codigoInterno: 'P-001',
              descricao: 'Produto teste',
              origemCadastro: ProductSource.manual,
              status: ProductStatus.active,
              ncm: '84212300',
              cest: '0100100',
              aliquotaIpiBase: 0,
            ),
          ],
        ),
        basePriceRepository: _FakeProductBasePriceRepository(
          items: const <ProductBasePrice>[
            ProductBasePrice(
              id: 'pbp-1',
              tenantId: tenantId,
              productId: produtoId,
              priceTableId: tabelaId,
              regionId: 'SP',
              basePrice: 100,
              status: 'active',
            ),
          ],
        ),
        taxRuleRepository: _FakeTaxRuleRepository(
          items: const <TaxRule>[
            TaxRule(
              id: 'global-rule',
              tenantId: tenantId,
              representedCompanyId: null,
              status: 'active',
              ufOrigem: 'SP',
              ufDestino: 'SP',
              ncm: '84212300',
              stCalculationType: 'mva',
              mvaIva: 40,
              aliquotaCredito: 12,
              aliquotaDestino: 18,
              aliquotaDifal: 5,
              priority: 10,
            ),
          ],
        ),
      );

      final result = await localService.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        salePurpose: SalePurpose.revenda,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        representedCompanyId: representedCompanyId,
        ufOrigem: 'SP',
      );

      expect(result.regraFiscalId, 'global-rule');
      expect(result.valorSt, closeTo(13.2, 0.0001));
      expect(result.valorDifal, 0);
      expect(result.operationProfileKey, 'revenda_same_uf');
    });

    test('prioritizes tax group rule over ncm-only rule', () async {
      final localService = ProductTaxEngineService(
        produtoRepository: _FakeProdutoRepository(
          items: const <Produto>[
            Produto(
              id: produtoId,
              tenantId: tenantId,
              codigoInterno: 'P-001',
              descricao: 'Produto teste',
              origemCadastro: ProductSource.manual,
              status: ProductStatus.active,
              grupoTributarioId: 'grp-1',
              ncm: '84212300',
              cest: '0100100',
              aliquotaIpiBase: 0,
            ),
          ],
        ),
        basePriceRepository: _FakeProductBasePriceRepository(
          items: const <ProductBasePrice>[
            ProductBasePrice(
              id: 'pbp-1',
              tenantId: tenantId,
              productId: produtoId,
              priceTableId: tabelaId,
              regionId: 'SP',
              basePrice: 100,
              status: 'active',
            ),
          ],
        ),
        taxRuleRepository: _FakeTaxRuleRepository(
          items: const <TaxRule>[
            TaxRule(
              id: 'rule-ncm',
              tenantId: tenantId,
              representedCompanyId: representedCompanyId,
              status: 'active',
              ufOrigem: 'SP',
              ufDestino: 'SP',
              ncm: '84212300',
              stCalculationType: 'mva',
              mvaIva: 40,
              aliquotaCredito: 12,
              aliquotaDestino: 18,
              priority: 5,
            ),
            TaxRule(
              id: 'rule-group',
              tenantId: tenantId,
              representedCompanyId: representedCompanyId,
              status: 'active',
              ufOrigem: 'SP',
              ufDestino: 'SP',
              taxGroupId: 'grp-1',
              stCalculationType: 'mva',
              mvaIva: 40,
              aliquotaCredito: 12,
              aliquotaDestino: 17,
              priority: 1,
            ),
          ],
        ),
      );

      final result = await localService.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        salePurpose: SalePurpose.revenda,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        representedCompanyId: representedCompanyId,
        ufOrigem: 'SP',
      );

      expect(result.regraFiscalId, 'rule-group');
    });
  });

  group('ProductTaxEngineService matcher fallback chain (P0.1)', () {
    const tenantId = 'tenant-1';
    const produtoId = 'prod-1';
    const tabelaId = 'tab-1';

    ProductTaxEngineService buildService({
      required Produto produto,
      required List<TaxRule> rules,
    }) {
      return ProductTaxEngineService(
        produtoRepository: _FakeProdutoRepository(items: <Produto>[produto]),
        basePriceRepository: _FakeProductBasePriceRepository(
          items: <ProductBasePrice>[
            const ProductBasePrice(
              id: 'pbp-1',
              tenantId: tenantId,
              productId: produtoId,
              priceTableId: tabelaId,
              regionId: 'SP',
              basePrice: 100,
              status: 'active',
            ),
          ],
        ),
        taxRuleRepository: _FakeTaxRuleRepository(items: rules),
      );
    }

    const produto = Produto(
      id: produtoId,
      tenantId: tenantId,
      codigoInterno: 'P-001',
      descricao: 'Produto teste',
      origemCadastro: ProductSource.manual,
      status: ProductStatus.active,
      grupoTributarioId: 'grp-1',
      ncm: '84212300',
      cest: '0100100',
      aliquotaIpiBase: 0,
    );

    test('tier 0: produto-specific rule wins over group/ncm/generic rules', () async {
      final service = buildService(
        produto: produto,
        rules: const <TaxRule>[
          TaxRule(
            id: 'rule-generic-uf',
            tenantId: tenantId,
            status: 'active',
            ufOrigem: 'SP',
            ufDestino: 'SP',
            aliquotaCredito: 12,
            aliquotaDestino: 10,
            priority: 100,
          ),
          TaxRule(
            id: 'rule-ncm',
            tenantId: tenantId,
            status: 'active',
            ufOrigem: 'SP',
            ufDestino: 'SP',
            ncm: '84212300',
            aliquotaCredito: 12,
            aliquotaDestino: 15,
            priority: 100,
          ),
          TaxRule(
            id: 'rule-group',
            tenantId: tenantId,
            status: 'active',
            ufOrigem: 'SP',
            ufDestino: 'SP',
            taxGroupId: 'grp-1',
            aliquotaCredito: 12,
            aliquotaDestino: 17,
            priority: 100,
          ),
          TaxRule(
            id: 'rule-produto',
            tenantId: tenantId,
            status: 'active',
            ufOrigem: 'SP',
            ufDestino: 'SP',
            produtoId: produtoId,
            aliquotaCredito: 12,
            aliquotaDestino: 18,
            priority: 1,
          ),
        ],
      );

      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        ufOrigem: 'SP',
      );

      expect(result.regraFiscalId, 'rule-produto');
    });

    test('tier 3: falls back to generic UF-only rule when no produto/group/ncm rule matches', () async {
      final produtoSemMatch = produto.copyWith(ncm: '99999999', cest: null);
      final service = buildService(
        produto: produtoSemMatch,
        rules: const <TaxRule>[
          TaxRule(
            id: 'rule-other-ncm',
            tenantId: tenantId,
            status: 'active',
            ufOrigem: 'SP',
            ufDestino: 'SP',
            ncm: '12345678',
            aliquotaCredito: 12,
            aliquotaDestino: 15,
          ),
          TaxRule(
            id: 'rule-generic-uf',
            tenantId: tenantId,
            status: 'active',
            ufOrigem: 'SP',
            ufDestino: 'SP',
            aliquotaCredito: 12,
            aliquotaDestino: 10,
          ),
        ],
      );

      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        ufOrigem: 'SP',
      );

      expect(result.regraFiscalId, 'rule-generic-uf');
    });
  });

  group('ProductTaxEngineService buyer tax regime tie-break (P1.2)', () {
    const tenantId = 'tenant-1';
    const produtoId = 'prod-1';
    const tabelaId = 'tab-1';

    const produto = Produto(
      id: produtoId,
      tenantId: tenantId,
      codigoInterno: 'P-001',
      descricao: 'Produto teste',
      origemCadastro: ProductSource.manual,
      status: ProductStatus.active,
      ncm: '84212300',
      aliquotaIpiBase: 0,
    );

    ProductTaxEngineService buildService(List<TaxRule> rules) {
      return ProductTaxEngineService(
        produtoRepository: _FakeProdutoRepository(items: const <Produto>[produto]),
        basePriceRepository: _FakeProductBasePriceRepository(
          items: const <ProductBasePrice>[
            ProductBasePrice(
              id: 'pbp-1',
              tenantId: tenantId,
              productId: produtoId,
              priceTableId: tabelaId,
              regionId: 'SP',
              basePrice: 100,
              status: 'active',
            ),
          ],
        ),
        taxRuleRepository: _FakeTaxRuleRepository(items: rules),
      );
    }

    const rules = <TaxRule>[
      TaxRule(
        id: 'rule-simples',
        tenantId: tenantId,
        status: 'active',
        ufOrigem: 'SP',
        ufDestino: 'SP',
        ncm: '84212300',
        applicableBuyerTaxRegime: 'simples_nacional',
        aliquotaCredito: 12,
        aliquotaDestino: 12,
      ),
      TaxRule(
        id: 'rule-default',
        tenantId: tenantId,
        status: 'active',
        ufOrigem: 'SP',
        ufDestino: 'SP',
        ncm: '84212300',
        aliquotaCredito: 12,
        aliquotaDestino: 18,
      ),
    ];

    test('selects buyer-regime-specific rule when customer is Simples Nacional', () async {
      final service = buildService(rules);
      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        ufOrigem: 'SP',
        customerTaxRegime: 'simples_nacional',
      );

      expect(result.regraFiscalId, 'rule-simples');
    });

    test('falls back to default rule when customer tax regime does not match', () async {
      final service = buildService(rules);
      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        ufOrigem: 'SP',
        customerTaxRegime: 'lucro_presumido',
      );

      expect(result.regraFiscalId, 'rule-default');
    });
  });

  group('ProductTaxEngineService FCP calculation (P1.1)', () {
    const tenantId = 'tenant-1';
    const produtoId = 'prod-1';
    const tabelaId = 'tab-1';

    test('FCP and FCP-ST are added on top of ICMS/ST for revenda same UF', () async {
      final service = ProductTaxEngineService(
        produtoRepository: _FakeProdutoRepository(
          items: const <Produto>[
            Produto(
              id: produtoId,
              tenantId: tenantId,
              codigoInterno: 'P-001',
              descricao: 'Produto teste',
              origemCadastro: ProductSource.manual,
              status: ProductStatus.active,
              ncm: '84212300',
              aliquotaIpiBase: 0,
            ),
          ],
        ),
        basePriceRepository: _FakeProductBasePriceRepository(
          items: const <ProductBasePrice>[
            ProductBasePrice(
              id: 'pbp-1',
              tenantId: tenantId,
              productId: produtoId,
              priceTableId: tabelaId,
              regionId: 'SP',
              basePrice: 100,
              status: 'active',
            ),
          ],
        ),
        taxRuleRepository: _FakeTaxRuleRepository(
          items: const <TaxRule>[
            TaxRule(
              id: 'rule-fcp-st',
              tenantId: tenantId,
              status: 'active',
              ufOrigem: 'SP',
              ufDestino: 'SP',
              ncm: '84212300',
              stCalculationType: 'mva',
              mvaIva: 40,
              aliquotaCredito: 12,
              aliquotaDestino: 18,
              aliquotaFcp: 2,
              aliquotaFcpSt: 2,
            ),
          ],
        ),
      );

      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        salePurpose: SalePurpose.revenda,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        ufOrigem: 'SP',
      );

      // FCP: 2% sobre base ICMS (100) = 2.0
      expect(result.valorFcp, closeTo(2.0, 0.0001));
      // FCP-ST: 2% sobre a base ST (140, com MVA 40%) = 2.8
      expect(result.valorFcpSt, closeTo(2.8, 0.0001));
      expect(
        result.valorTotalItem,
        closeTo(
          result.valorLiquido +
              result.valorIpi +
              result.valorSt +
              result.valorDifal +
              result.valorFcp +
              result.valorFcpSt +
              result.valorFcpDifal,
          0.0001,
        ),
      );
    });

    test('FCP-DIFAL is added for uso/consumo interstate contribuinte', () async {
      final service = ProductTaxEngineService(
        produtoRepository: _FakeProdutoRepository(
          items: const <Produto>[
            Produto(
              id: produtoId,
              tenantId: tenantId,
              codigoInterno: 'P-001',
              descricao: 'Produto teste',
              origemCadastro: ProductSource.manual,
              status: ProductStatus.active,
              ncm: '84212300',
              aliquotaIpiBase: 0,
            ),
          ],
        ),
        basePriceRepository: _FakeProductBasePriceRepository(
          items: const <ProductBasePrice>[
            ProductBasePrice(
              id: 'pbp-1',
              tenantId: tenantId,
              productId: produtoId,
              priceTableId: tabelaId,
              regionId: 'RJ',
              basePrice: 100,
              status: 'active',
            ),
          ],
        ),
        taxRuleRepository: _FakeTaxRuleRepository(
          items: const <TaxRule>[
            TaxRule(
              id: 'rule-fcp-difal',
              tenantId: tenantId,
              status: 'active',
              ufOrigem: 'SP',
              ufDestino: 'RJ',
              ncm: '84212300',
              aliquotaCredito: 12,
              aliquotaDestino: 18,
              aliquotaDifal: 8,
              aliquotaFcpDifal: 2,
            ),
          ],
        ),
      );

      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'RJ',
        quantidade: 1,
        salePurpose: SalePurpose.usoConsumo,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        ufOrigem: 'SP',
      );

      expect(result.valorDifal, closeTo(8.0, 0.0001));
      expect(result.valorFcpDifal, closeTo(2.0, 0.0001));
    });
  });

  group('ProductTaxEngineService dynamic operation profile overrides (P0.2)', () {
    const tenantId = 'tenant-1';
    const representedCompanyId = 'rep-1';
    const produtoId = 'prod-1';
    const tabelaId = 'tab-1';

    test('respects an active override that disables ST for revenda_same_uf', () async {
      final service = ProductTaxEngineService(
        produtoRepository: _FakeProdutoRepository(
          items: const <Produto>[
            Produto(
              id: produtoId,
              tenantId: tenantId,
              codigoInterno: 'P-001',
              descricao: 'Produto teste',
              origemCadastro: ProductSource.manual,
              status: ProductStatus.active,
              ncm: '84212300',
              aliquotaIpiBase: 0,
            ),
          ],
        ),
        basePriceRepository: _FakeProductBasePriceRepository(
          items: const <ProductBasePrice>[
            ProductBasePrice(
              id: 'pbp-1',
              tenantId: tenantId,
              productId: produtoId,
              priceTableId: tabelaId,
              regionId: 'SP',
              basePrice: 100,
              status: 'active',
            ),
          ],
        ),
        taxRuleRepository: _FakeTaxRuleRepository(
          items: const <TaxRule>[
            TaxRule(
              id: 'rule-1',
              tenantId: tenantId,
              representedCompanyId: representedCompanyId,
              status: 'active',
              ufOrigem: 'SP',
              ufDestino: 'SP',
              ncm: '84212300',
              stCalculationType: 'mva',
              mvaIva: 40,
              aliquotaCredito: 12,
              aliquotaDestino: 18,
            ),
          ],
        ),
        taxOperationProfileRepository: _FakeTaxOperationProfileRepository(
          items: <TaxOperationProfile>[
            TaxOperationProfile(
              id: 'override-1',
              tenantId: tenantId,
              representedCompanyId: representedCompanyId,
              profileKey: 'revenda_same_uf',
              status: 'active',
              priority: 10,
              calculateIcmsSt: false,
              calculateDifal: false,
              includeIpiInIcmsBase: false,
              addIpiToTotal: false,
              reduceIcmsForZfm: false,
            ),
          ],
        ),
      );

      final result = await service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        salePurpose: SalePurpose.revenda,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        representedCompanyId: representedCompanyId,
        ufOrigem: 'SP',
      );

      expect(result.valorSt, 0);
      expect(result.valorTotalItem, result.valorLiquido);
    });
  });

  group('ProductTaxEngineService golden tests - validated SP ICMS-ST cases', () {
    const tenantId = 'tenant-1';
    const produtoId = 'prod-1';
    const tabelaId = 'tab-1';

    Future<ProductTaxCalculationResult> runCase({
      required double aliquotaIpi,
      required double aliquotaIcms,
      required double mva,
      double? reductionPercent,
      bool reductionAppliesToIcmsProprio = false,
    }) {
      final service = ProductTaxEngineService(
        produtoRepository: _FakeProdutoRepository(
          items: <Produto>[
            Produto(
              id: produtoId,
              tenantId: tenantId,
              codigoInterno: 'P-001',
              descricao: 'Produto teste',
              origemCadastro: ProductSource.manual,
              status: ProductStatus.active,
              ncm: '84212300',
              aliquotaIpiBase: aliquotaIpi,
            ),
          ],
        ),
        basePriceRepository: _FakeProductBasePriceRepository(
          items: const <ProductBasePrice>[
            ProductBasePrice(
              id: 'pbp-1',
              tenantId: tenantId,
              productId: produtoId,
              priceTableId: tabelaId,
              regionId: 'SP',
              basePrice: 100,
              status: 'active',
            ),
          ],
        ),
        taxRuleRepository: _FakeTaxRuleRepository(
          items: <TaxRule>[
            TaxRule(
              id: 'rule-golden',
              tenantId: tenantId,
              status: 'active',
              ufOrigem: 'SP',
              ufDestino: 'SP',
              ncm: '84212300',
              stCalculationType: 'mva',
              mvaIva: mva,
              aliquotaCredito: aliquotaIcms,
              aliquotaDestino: aliquotaIcms,
              stBaseReductionPercent: reductionPercent,
              stReductionAppliesToIcmsProprio: reductionAppliesToIcmsProprio,
            ),
          ],
        ),
      );

      return service.calcularTotaisItem(
        tenantId: tenantId,
        produtoId: produtoId,
        tabelaId: tabelaId,
        clienteUf: 'SP',
        quantidade: 1,
        salePurpose: SalePurpose.revenda,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        ufOrigem: 'SP',
      );
    }

    test('NCM 73269090-like: IPI 5%, ICMS 18%, MVA 179% => ST ~34.73', () async {
      final result = await runCase(aliquotaIpi: 5, aliquotaIcms: 18, mva: 179);
      expect(result.valorSt, closeTo(34.73, 0.01));
    });

    test('NCM 39269090-like: IPI 9.75%, ICMS 18%, MVA 120% => ST ~25.46', () async {
      final result = await runCase(aliquotaIpi: 9.75, aliquotaIcms: 18, mva: 120);
      expect(result.valorSt, closeTo(25.46, 0.01));
    });

    test(
      'NCM 85044010-like: IPI 5%, ICMS 18%, MVA 78%, base reduzida para 48.89% '
      'tambem no ICMS proprio => ST ~7.65',
      () async {
        final result = await runCase(
          aliquotaIpi: 5,
          aliquotaIcms: 18,
          mva: 78,
          reductionPercent: 51.11,
          reductionAppliesToIcmsProprio: true,
        );
        expect(result.valorSt, closeTo(7.65, 0.01));
      },
    );
  });
}

class _FakeProdutoRepository implements ProdutoRepository {
  _FakeProdutoRepository({required List<Produto> items})
    : _items = List<Produto>.from(items);

  final List<Produto> _items;

  @override
  Future<List<Produto>> fetchAll({required String tenantId}) async {
    return _items.where((item) => item.tenantId == tenantId).toList();
  }

  @override
  Future<Produto?> fetchById({required String tenantId, required String id}) async {
    for (final item in _items) {
      if (item.tenantId == tenantId && item.id == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> save(Produto entity) async {
    _items.removeWhere((item) => item.id == entity.id && item.tenantId == entity.tenantId);
    _items.add(entity);
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {
    _items.removeWhere((item) => item.tenantId == tenantId && item.id == id);
  }

  @override
  Stream<List<Produto>> watchAll({required String tenantId}) {
    return Stream<List<Produto>>.value(
      _items.where((item) => item.tenantId == tenantId).toList(),
    );
  }
}

class _FakeProductBasePriceRepository implements ProductBasePriceRepository {
  _FakeProductBasePriceRepository({required List<ProductBasePrice> items})
    : _items = List<ProductBasePrice>.from(items);

  final List<ProductBasePrice> _items;

  @override
  Future<List<ProductBasePrice>> fetchAll({required String tenantId}) async {
    return _items.where((item) => item.tenantId == tenantId).toList();
  }

  @override
  Future<ProductBasePrice?> fetchById({
    required String tenantId,
    required String id,
  }) async {
    for (final item in _items) {
      if (item.tenantId == tenantId && item.id == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> save(ProductBasePrice entity) async {
    _items.removeWhere((item) => item.id == entity.id && item.tenantId == entity.tenantId);
    _items.add(entity);
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {
    _items.removeWhere((item) => item.tenantId == tenantId && item.id == id);
  }

  @override
  Stream<List<ProductBasePrice>> watchAll({required String tenantId}) {
    return Stream<List<ProductBasePrice>>.value(
      _items.where((item) => item.tenantId == tenantId).toList(),
    );
  }
}

class _FakeTaxRuleRepository implements TaxRuleRepository {
  _FakeTaxRuleRepository({required List<TaxRule> items})
    : _items = List<TaxRule>.from(items);

  final List<TaxRule> _items;

  @override
  Future<List<TaxRule>> fetchAll({required String tenantId}) async {
    return _items.where((item) => item.tenantId == tenantId).toList();
  }

  @override
  Future<TaxRule?> fetchById({required String tenantId, required String id}) async {
    for (final item in _items) {
      if (item.tenantId == tenantId && item.id == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> save(TaxRule entity) async {
    _items.removeWhere((item) => item.id == entity.id && item.tenantId == entity.tenantId);
    _items.add(entity);
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {
    _items.removeWhere((item) => item.tenantId == tenantId && item.id == id);
  }

  @override
  Stream<List<TaxRule>> watchAll({required String tenantId}) {
    return Stream<List<TaxRule>>.value(
      _items.where((item) => item.tenantId == tenantId).toList(),
    );
  }
}

class _FakeTaxOperationProfileRepository
    implements TaxOperationProfileRepository {
  _FakeTaxOperationProfileRepository({required List<TaxOperationProfile> items})
    : _items = List<TaxOperationProfile>.from(items);

  final List<TaxOperationProfile> _items;

  @override
  Future<List<TaxOperationProfile>> fetchAll({required String tenantId}) async {
    return _items.where((item) => item.tenantId == tenantId).toList();
  }

  @override
  Future<TaxOperationProfile?> fetchById({
    required String tenantId,
    required String id,
  }) async {
    for (final item in _items) {
      if (item.tenantId == tenantId && item.id == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> save(TaxOperationProfile entity) async {
    _items.removeWhere((item) => item.id == entity.id && item.tenantId == entity.tenantId);
    _items.add(entity);
  }

  @override
  Future<void> delete({required String tenantId, required String id}) async {
    _items.removeWhere((item) => item.tenantId == tenantId && item.id == id);
  }

  @override
  Stream<List<TaxOperationProfile>> watchAll({required String tenantId}) {
    return Stream<List<TaxOperationProfile>>.value(
      _items.where((item) => item.tenantId == tenantId).toList(),
    );
  }
}
