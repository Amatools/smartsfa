import 'dart:math' as math;

import '../../../core/models/product_base_price.dart';
import '../../../core/models/tax_rule.dart';
import '../../../core/models/domain_types.dart';
import '../../../core/repositories/product_base_price_repository.dart';
import '../../../core/repositories/produto_repository.dart';
import '../../../core/repositories/tax_rule_repository.dart';

class ProductTaxCalculationResult {
  const ProductTaxCalculationResult({
    required this.precoBase,
    required this.valorIpi,
    required this.valorSt,
    required this.valorLiquido,
    required this.valorTotalItem,
    required this.tabelaId,
    required this.ufDestino,
    this.valorDifal = 0,
    this.regraFiscalId,
    this.ncm,
    this.cest,
  });

  final double precoBase;
  final double valorIpi;
  final double valorSt;
  final double valorDifal;

  // Valor liquido = subtotal sem impostos adicionais por fora.
  final double valorLiquido;

  // Total final com impostos por fora.
  final double valorTotalItem;

  final String tabelaId;
  final String ufDestino;
  final String? regraFiscalId;
  final String? ncm;
  final String? cest;
}

class ProductTaxEngineService {
  ProductTaxEngineService({
    required this.produtoRepository,
    required this.basePriceRepository,
    required this.taxRuleRepository,
  });

  final ProdutoRepository produtoRepository;
  final ProductBasePriceRepository basePriceRepository;
  final TaxRuleRepository taxRuleRepository;
  final Map<String, List<ProductBasePrice>> _basePricesCache =
      <String, List<ProductBasePrice>>{};
  final Map<String, List<TaxRule>> _taxRulesCache = <String, List<TaxRule>>{};

  Future<ProductTaxCalculationResult> calcularTotaisItem({
    required String tenantId,
    required String produtoId,
    required String tabelaId,
    required String clienteUf,
    required double quantidade,
    SalePurpose salePurpose = SalePurpose.revenda,
    CustomerTaxProfile customerTaxProfile = CustomerTaxProfile.contribuinte,
    bool isZonaFrancaSuframa = false,
    String? representedCompanyId,
    String ufOrigem = 'SP',
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedProdutoId = produtoId.trim();
    final normalizedTabelaId = tabelaId.trim();
    final normalizedUfDestino = clienteUf.trim().toUpperCase();
    final normalizedUfOrigem = ufOrigem.trim().toUpperCase();
    final normalizedRepresentedCompanyId = (representedCompanyId ?? '').trim();

    if (normalizedTenantId.isEmpty ||
        normalizedProdutoId.isEmpty ||
        normalizedTabelaId.isEmpty ||
        normalizedUfDestino.isEmpty) {
      throw StateError('Parametros invalidos para calcular totais do item.');
    }

    if (quantidade <= 0) {
      throw StateError('Quantidade deve ser maior que zero.');
    }

    final produto = await produtoRepository.fetchById(
      tenantId: normalizedTenantId,
      id: normalizedProdutoId,
    );
    if (produto == null) {
      throw StateError('Produto nao encontrado.');
    }

    final precoBaseRegistro = await _resolveBasePrice(
      tenantId: normalizedTenantId,
      produtoId: normalizedProdutoId,
      tabelaId: normalizedTabelaId,
      ufDestino: normalizedUfDestino,
    );
    if (precoBaseRegistro == null) {
      throw StateError(
        'Preco base nao encontrado para produto/tabela/UF selecionados.',
      );
    }

    final regras = await _loadTaxRules(normalizedTenantId);
    final scopedRules = regras
        .where((rule) {
          final scope = (rule.representedCompanyId ?? '').trim();
          if (scope.isEmpty) {
            return true;
          }
          return scope == normalizedRepresentedCompanyId;
        })
        .toList(growable: false);
    final regra = _resolveTaxRule(
      regras: scopedRules,
      ncm: produto.ncm,
      cest: produto.cest,
      ufOrigem: normalizedUfOrigem,
      ufDestino: normalizedUfDestino,
      salePurpose: salePurpose,
    );

    final precoBaseOriginal = precoBaseRegistro.basePrice * quantidade;
    final precoUnitario = precoBaseRegistro.basePrice;

    // For ZFM/SUFRAMA, instead of adding tax over the item total, we discount
    // the product value by the configured ICMS destination rate.
    final zfmDiscountRate = isZonaFrancaSuframa
      ? (regra?.aliquotaDestino ??
          regra?.aliquotaSt ??
          regra?.aliquotaIcms ??
          regra?.aliquotaCredito ??
          0.0)
      : 0.0;
    final zfmDiscountValue = isZonaFrancaSuframa
      ? precoBaseOriginal * (zfmDiscountRate / 100)
      : 0.0;
    final precoBase = isZonaFrancaSuframa
      ? math.max(precoBaseOriginal - zfmDiscountValue, 0.0)
      : precoBaseOriginal;

    final aliquotaIpi = produto.aliquotaIpiBase ?? 0;
    final valorIpi = precoBase * (aliquotaIpi / 100);

    final double aliquotaCredito =
      regra?.aliquotaCredito ?? regra?.aliquotaIcms ?? 0.0;
    final double aliquotaDestino =
      regra?.aliquotaDestino ?? regra?.aliquotaSt ?? 0.0;
    final double mvaIva = regra?.mvaIva ?? 0.0;
    final tipoSt = (regra?.stCalculationType ?? 'mva').trim().toLowerCase();
    final isMva = tipoSt != 'pmc';
    final isUsoConsumo = salePurpose == SalePurpose.usoConsumo;
    final applySt = !isZonaFrancaSuframa &&
      (!isUsoConsumo ||
          customerTaxProfile == CustomerTaxProfile.contribuinte);
    final applyDifal = !isZonaFrancaSuframa &&
      (!isUsoConsumo ||
          customerTaxProfile == CustomerTaxProfile.naoContribuinte);

    double valorSt = 0;
    if (applySt && aliquotaDestino > 0) {
      final baseSt = _resolveStBase(
        isMva: isMva,
        precoBase: precoBase,
        precoUnitario: precoUnitario,
        quantidade: quantidade,
        precoConsiderado: regra?.stPriceForCalculation,
        mvaIva: mvaIva,
        reducaoBase: regra?.stBaseReductionPercent,
        baseCalculoPmc: regra?.stBaseAmount,
      );
      final icmsProprio = precoBase * (aliquotaCredito / 100);
      final icmsStCheio = baseSt * (aliquotaDestino / 100);
      valorSt = math.max(icmsStCheio - icmsProprio, 0.0);
    }

    final double aliquotaDifal = regra?.aliquotaDifal ?? 0.0;
    final valorDifal = applyDifal ? precoBase * (aliquotaDifal / 100) : 0.0;

    final valorLiquido = precoBase;
    final valorTotalItem = valorLiquido + valorIpi + valorSt + valorDifal;

    return ProductTaxCalculationResult(
      precoBase: precoBase,
      valorIpi: valorIpi,
      valorSt: valorSt,
      valorDifal: valorDifal,
      valorLiquido: valorLiquido,
      valorTotalItem: valorTotalItem,
      tabelaId: precoBaseRegistro.priceTableId,
      ufDestino: normalizedUfDestino,
      regraFiscalId: regra?.id,
      ncm: produto.ncm,
      cest: produto.cest,
    );
  }

  Future<ProductBasePrice?> _resolveBasePrice({
    required String tenantId,
    required String produtoId,
    required String tabelaId,
    required String ufDestino,
  }) async {
    final all = await _loadBasePrices(tenantId);
    final filtered = all
        .where((item) {
          return item.isActive &&
              item.productId == produtoId &&
              item.priceTableId == tabelaId;
        })
        .toList(growable: false);

    final normalizedUf = ufDestino.toUpperCase();
    for (final item in filtered) {
      if (item.regionId.trim().toUpperCase() == normalizedUf) {
        return item;
      }
    }

    for (final item in filtered) {
      final normalized = item.regionId.trim().toUpperCase();
      if (normalized.isEmpty ||
          normalized == 'ALL' ||
          normalized == 'BR' ||
          normalized == 'DEFAULT') {
        return item;
      }
    }

    return null;
  }

  TaxRule? _resolveTaxRule({
    required List<TaxRule> regras,
    required String? ncm,
    required String? cest,
    required String ufOrigem,
    required String ufDestino,
    required SalePurpose salePurpose,
  }) {
    final normalizedNcm = _normalizeNcm(ncm);
    if (normalizedNcm.isEmpty) {
      return null;
    }
    final normalizedCest = _normalizeCest(cest);
    final now = DateTime.now().toUtc();

    final candidates = <({TaxRule regra, bool matchedByCest})>[];
    for (final regra in regras) {
      if (!regra.isActive) {
        continue;
      }

      if (!_isInDateWindow(regra.validFrom, regra.validUntil, now)) {
        continue;
      }

      final regraNcm = _normalizeNcm(regra.ncm);
      if (regraNcm != normalizedNcm) {
        continue;
      }

      final origem = regra.ufOrigem.trim().toUpperCase();
      if (origem.isNotEmpty && origem != 'ANY' && origem != ufOrigem) {
        continue;
      }

      final destino = regra.ufDestino.trim().toUpperCase();
      if (destino.isNotEmpty && destino != 'ANY' && destino != ufDestino) {
        continue;
      }

      if (regra.salePurpose != null && regra.salePurpose != salePurpose) {
        continue;
      }

      final regraCest = _normalizeCest(regra.cest);
      if (regraCest.isNotEmpty) {
        if (normalizedCest.isEmpty || regraCest != normalizedCest) {
          continue;
        }
        candidates.add((regra: regra, matchedByCest: true));
        continue;
      }

      candidates.add((regra: regra, matchedByCest: false));
    }

    candidates.sort((a, b) {
      if (a.matchedByCest != b.matchedByCest) {
        return b.matchedByCest ? 1 : -1;
      }
      return b.regra.priority.compareTo(a.regra.priority);
    });

    return candidates.isEmpty ? null : candidates.first.regra;
  }

  bool _isInDateWindow(
    DateTime? validFrom,
    DateTime? validUntil,
    DateTime now,
  ) {
    if (validFrom != null && now.isBefore(validFrom)) {
      return false;
    }
    if (validUntil != null && now.isAfter(validUntil)) {
      return false;
    }
    return true;
  }

  double _resolveStBase({
    required bool isMva,
    required double precoBase,
    required double precoUnitario,
    required double quantidade,
    required double? precoConsiderado,
    required double mvaIva,
    required double? reducaoBase,
    required double? baseCalculoPmc,
  }) {
    if (!isMva) {
      if (baseCalculoPmc != null && baseCalculoPmc > 0) {
        return baseCalculoPmc * quantidade;
      }
      return precoBase;
    }

    final precoReferenciaUnitario =
        precoConsiderado != null && precoConsiderado > 0
        ? precoConsiderado
        : precoUnitario;
    final percentualReducao = math.min(math.max(reducaoBase ?? 0, 0), 100);

    final baseBruta =
        precoReferenciaUnitario * quantidade * (1 + (mvaIva / 100));
    return baseBruta * (1 - (percentualReducao / 100));
  }

  String _normalizeNcm(String? value) {
    final source = (value ?? '').trim();
    if (source.isEmpty) {
      return '';
    }
    return source.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _normalizeCest(String? value) {
    final source = (value ?? '').trim();
    if (source.isEmpty) {
      return '';
    }
    return source.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<List<ProductBasePrice>> _loadBasePrices(String tenantId) async {
    final cached = _basePricesCache[tenantId];
    if (cached != null) {
      return cached;
    }

    final loaded = await basePriceRepository.fetchAll(tenantId: tenantId);
    _basePricesCache[tenantId] = List<ProductBasePrice>.unmodifiable(loaded);
    return loaded;
  }

  Future<List<TaxRule>> _loadTaxRules(String tenantId) async {
    final cached = _taxRulesCache[tenantId];
    if (cached != null) {
      return cached;
    }

    final loaded = await taxRuleRepository.fetchAll(tenantId: tenantId);
    _taxRulesCache[tenantId] = List<TaxRule>.unmodifiable(loaded);
    return loaded;
  }
}
