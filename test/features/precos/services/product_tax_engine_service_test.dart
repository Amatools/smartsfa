import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/core/models/domain_types.dart';
import 'package:smartsfa/src/core/models/product_base_price.dart';
import 'package:smartsfa/src/core/models/produto.dart';
import 'package:smartsfa/src/core/models/tax_rule.dart';
import 'package:smartsfa/src/core/repositories/product_base_price_repository.dart';
import 'package:smartsfa/src/core/repositories/produto_repository.dart';
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
            salePurpose: SalePurpose.usoConsumo,
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

    test('applies ST and suppresses DIFAL for contribuinte on uso/consumo', () async {
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
      expect(result.valorSt, closeTo(13.2, 0.0001));
      expect(result.valorDifal, 0);
      expect(result.valorTotalItem, closeTo(113.2, 0.0001));
    });

    test('suppresses ST and applies DIFAL for nao contribuinte on uso/consumo', () async {
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
      expect(result.valorDifal, closeTo(5, 0.0001));
      expect(result.valorTotalItem, closeTo(105, 0.0001));
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
              salePurpose: SalePurpose.revenda,
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
              salePurpose: SalePurpose.revenda,
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
      expect(result.valorDifal, closeTo(5, 0.0001));
    });
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
