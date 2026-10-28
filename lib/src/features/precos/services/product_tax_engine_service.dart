import 'dart:math' as math;

import '../../../core/models/product_base_price.dart';
import '../../../core/models/tax_operation_profile.dart';
import '../../../core/models/tax_rule.dart';
import '../../../core/models/domain_types.dart';
import '../../../core/repositories/product_base_price_repository.dart';
import '../../../core/repositories/produto_repository.dart';
import '../../../core/repositories/tax_operation_profile_repository.dart';
import '../../../core/repositories/tax_rule_repository.dart';
import 'tax_operation_classifier_service.dart';
import 'tax_rounding_policy.dart';

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
    this.valorFcp = 0,
    this.valorFcpSt = 0,
    this.valorFcpDifal = 0,
    this.regraFiscalId,
    this.ncm,
    this.cest,
    this.operationProfileKey,
    this.matchedTier,
    this.matchedByCest = false,
    this.matchedByBuyerRegime = false,
    this.operationProfileSource = 'native',
    this.operationProfileOverrideId,
  });

  final double precoBase;
  final double valorIpi;
  final double valorSt;
  final double valorDifal;
  final double valorFcp;
  final double valorFcpSt;
  final double valorFcpDifal;

  // Valor liquido = subtotal sem impostos adicionais por fora.
  final double valorLiquido;

  // Total final com impostos por fora.
  final double valorTotalItem;

  final String tabelaId;
  final String ufDestino;
  final String? regraFiscalId;
  final String? ncm;
  final String? cest;
  final String? operationProfileKey;

  /// Nivel do matcher que selecionou a regra fiscal (0=produto especifico,
  /// 1=grupo tributario, 2=NCM, 3=regra geral por UF). `null` quando nenhuma
  /// regra foi encontrada. Usado pela tela de auditoria fiscal (P1.4).
  final int? matchedTier;

  /// Se a regra escolhida desempatou por CEST dentro do mesmo nivel.
  final bool matchedByCest;

  /// Se a regra escolhida desempatou pelo regime tributario do comprador
  /// (ex.: MVA ajustado para Simples Nacional).
  final bool matchedByBuyerRegime;

  /// Origem do perfil de operacao aplicado: 'native' (padrao do motor) ou
  /// 'override' (veio de um documento ativo em `tax_operation_profiles`).
  final String operationProfileSource;

  /// Id do `TaxOperationProfile` usado, quando `operationProfileSource ==
  /// 'override'`.
  final String? operationProfileOverrideId;
}

/// Resultado interno do matcher (`_resolveTaxRule`), carregando nao so a
/// regra fiscal escolhida mas tambem o motivo da escolha, para alimentar a
/// tela de auditoria fiscal (P1.4).
class _TaxRuleMatch {
  const _TaxRuleMatch({
    required this.regra,
    required this.tier,
    required this.matchedByCest,
    required this.matchedByBuyerRegime,
  });

  final TaxRule regra;
  final int tier;
  final bool matchedByCest;
  final bool matchedByBuyerRegime;
}

class ProductTaxEngineService {
  ProductTaxEngineService({
    required this.produtoRepository,
    required this.basePriceRepository,
    required this.taxRuleRepository,
    this.taxOperationProfileRepository,
  });

  final ProdutoRepository produtoRepository;
  final ProductBasePriceRepository basePriceRepository;
  final TaxRuleRepository taxRuleRepository;
  final TaxOperationProfileRepository? taxOperationProfileRepository;
    final TaxOperationClassifierService _operationClassifier =
      const TaxOperationClassifierService();
  final Map<String, List<ProductBasePrice>> _basePricesCache =
      <String, List<ProductBasePrice>>{};
  final Map<String, List<TaxRule>> _taxRulesCache = <String, List<TaxRule>>{};
  final Map<String, List<TaxOperationProfile>> _taxOperationProfilesCache =
      <String, List<TaxOperationProfile>>{};

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
    String? customerTaxRegime,
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedProdutoId = produtoId.trim();
    final normalizedTabelaId = tabelaId.trim();
    final normalizedUfDestino = clienteUf.trim().toUpperCase();
    final normalizedUfOrigem = ufOrigem.trim().toUpperCase();
    final normalizedRepresentedCompanyId = (representedCompanyId ?? '').trim();
    final sameUf = normalizedUfOrigem == normalizedUfDestino;

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
    final ruleMatch = _resolveTaxRule(
      regras: scopedRules,
      produtoId: produto.id,
      productTaxGroupId: produto.grupoTributarioId,
      ncm: produto.ncm,
      cest: produto.cest,
      ufOrigem: normalizedUfOrigem,
      ufDestino: normalizedUfDestino,
      customerTaxRegime: customerTaxRegime,
    );
    final regra = ruleMatch?.regra;

    final precoBaseOriginal = precoBaseRegistro.basePrice * quantidade;
    final precoUnitario = precoBaseRegistro.basePrice;
    final operationProfiles = await _loadTaxOperationProfiles(
      normalizedTenantId,
    );
    final operationResolution = _operationClassifier.classify(
      salePurpose: salePurpose,
      sameUf: sameUf,
      customerTaxProfile: customerTaxProfile,
      isZonaFrancaSuframa: isZonaFrancaSuframa,
      overrides: operationProfiles,
      representedCompanyId: normalizedRepresentedCompanyId.isEmpty
          ? null
          : normalizedRepresentedCompanyId,
    );

    // For ZFM/SUFRAMA, instead of adding tax over the item total, we discount
    // the product value by the configured ICMS destination rate.
    final zfmDiscountRate = isZonaFrancaSuframa &&
          operationResolution.reduceIcmsForZfm
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
    final valorIpiCalculado = precoBase * (aliquotaIpi / 100);
    final valorIpi = operationResolution.addIpiToTotal ? valorIpiCalculado : 0.0;
    final baseIcms = operationResolution.includeIpiInIcmsBase
        ? precoBase + valorIpiCalculado
        : precoBase;

    final double aliquotaCredito =
      regra?.aliquotaCredito ?? regra?.aliquotaIcms ?? 0.0;
    final double aliquotaDestino =
      regra?.aliquotaDestino ?? regra?.aliquotaSt ?? 0.0;
    final double mvaIva = regra?.mvaIva ?? 0.0;
    final tipoSt = (regra?.stCalculationType ?? 'mva').trim().toLowerCase();
    final isMva = tipoSt != 'pmc';
    final applySt = operationResolution.calculateIcmsSt;
    final applyDifal = operationResolution.calculateDifal;

    // Fator de reducao de base ST (ver docs/tributacao_motor_especificacao_tecnica.md
    // secao 5c). Convencao: stBaseReductionPercent e o percentual a SUBTRAIR da
    // base cheia (ex.: 51.11 => base efetiva de 48.89%).
    final percentualReducao = math.min(
      math.max(regra?.stBaseReductionPercent ?? 0, 0),
      100,
    );
    final reductionFactor = 1 - (percentualReducao / 100);
    final reductionAppliesToIcmsProprio =
        (regra?.stReductionAppliesToIcmsProprio ?? false) &&
        percentualReducao > 0;
    final baseIcmsProprio = reductionAppliesToIcmsProprio
        ? baseIcms * reductionFactor
        : baseIcms;
    final icmsProprioParaAbatimento = baseIcmsProprio * (aliquotaCredito / 100);

    double valorSt = 0;
    double baseStResolvida = 0;
    if (applySt && aliquotaDestino > 0) {
      final baseSt = _resolveStBase(
        isMva: isMva,
        valorLiquidoItem: baseIcms,
        valorIpiItem: valorIpiCalculado,
        precoUnitario: precoUnitario,
        quantidade: quantidade,
        precoConsiderado: regra?.stPriceForCalculation,
        mvaIva: mvaIva,
        reductionFactor: reductionFactor,
        baseCalculoPmc: regra?.stBaseAmount,
      );
      baseStResolvida = baseSt;
      final icmsStCheio = baseSt * (aliquotaDestino / 100);
      valorSt = math.max(icmsStCheio - icmsProprioParaAbatimento, 0.0);
    }

    final double aliquotaDifal = regra?.aliquotaDifal ?? 0.0;
    final valorDifal = applyDifal ? precoBase * (aliquotaDifal / 100) : 0.0;

    // FCP (Fundo de Combate a Pobreza) - somado separadamente do ICMS/ST/DIFAL
    // (ver docs/tributacao_motor_especificacao_tecnica.md, secao 5e).
    final double aliquotaFcp = regra?.aliquotaFcp ?? 0.0;
    final double aliquotaFcpSt = regra?.aliquotaFcpSt ?? 0.0;
    final double aliquotaFcpDifal = regra?.aliquotaFcpDifal ?? 0.0;
    final valorFcp = aliquotaFcp > 0 ? baseIcms * (aliquotaFcp / 100) : 0.0;
    final valorFcpSt = applySt && aliquotaFcpSt > 0
        ? baseStResolvida * (aliquotaFcpSt / 100)
        : 0.0;
    final valorFcpDifal = applyDifal && aliquotaFcpDifal > 0
        ? precoBase * (aliquotaFcpDifal / 100)
        : 0.0;

    final valorIpiArredondado = TaxRoundingPolicy.roundCurrency(valorIpi);
    final valorStArredondado = TaxRoundingPolicy.roundCurrency(valorSt);
    final valorDifalArredondado = TaxRoundingPolicy.roundCurrency(valorDifal);
    final valorFcpArredondado = TaxRoundingPolicy.roundCurrency(valorFcp);
    final valorFcpStArredondado = TaxRoundingPolicy.roundCurrency(valorFcpSt);
    final valorFcpDifalArredondado = TaxRoundingPolicy.roundCurrency(
      valorFcpDifal,
    );

    final valorLiquido = precoBase;
    final valorTotalItem = TaxRoundingPolicy.roundCurrency(
      valorLiquido +
          valorIpiArredondado +
          valorStArredondado +
          valorDifalArredondado +
          valorFcpArredondado +
          valorFcpStArredondado +
          valorFcpDifalArredondado,
    );

    return ProductTaxCalculationResult(
      precoBase: precoBase,
      valorIpi: valorIpiArredondado,
      valorSt: valorStArredondado,
      valorDifal: valorDifalArredondado,
      valorFcp: valorFcpArredondado,
      valorFcpSt: valorFcpStArredondado,
      valorFcpDifal: valorFcpDifalArredondado,
      valorLiquido: valorLiquido,
      valorTotalItem: valorTotalItem,
      tabelaId: precoBaseRegistro.priceTableId,
      ufDestino: normalizedUfDestino,
      regraFiscalId: regra?.id,
      ncm: produto.ncm,
      cest: produto.cest,
      operationProfileKey: operationResolution.profileKey.value,
      matchedTier: ruleMatch?.tier,
      matchedByCest: ruleMatch?.matchedByCest ?? false,
      matchedByBuyerRegime: ruleMatch?.matchedByBuyerRegime ?? false,
      operationProfileSource: operationResolution.profileSource,
      operationProfileOverrideId: operationResolution.overrideId,
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

  _TaxRuleMatch? _resolveTaxRule({
    required List<TaxRule> regras,
    required String? produtoId,
    required String? productTaxGroupId,
    required String? ncm,
    required String? cest,
    required String ufOrigem,
    required String ufDestino,
    String? customerTaxRegime,
  }) {
    final normalizedProdutoId = (produtoId ?? '').trim().toLowerCase();
    final normalizedTaxGroupId = (productTaxGroupId ?? '').trim().toLowerCase();
    final normalizedNcm = _normalizeNcm(ncm);
    final normalizedCest = _normalizeCest(cest);
    final normalizedBuyerRegime = (customerTaxRegime ?? '').trim().toLowerCase();
    final now = DateTime.now().toUtc();

    // Cadeia de fallback (do mais especifico para o mais generico), ver
    // docs/tributacao_motor_especificacao_tecnica.md secao 5 (Passo 2):
    // 0 = produto especifico, 1 = grupo tributario, 2 = NCM,
    // 3 = regra geral por UF (sem produto/grupo/NCM).
    final candidates = <_TaxRuleMatch>[];
    for (final regra in regras) {
      if (!regra.isActive) {
        continue;
      }

      if (!_isInDateWindow(regra.validFrom, regra.validUntil, now)) {
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

      final regraProdutoId = (regra.produtoId ?? '').trim().toLowerCase();
      final matchedByProduto =
          regraProdutoId.isNotEmpty &&
          normalizedProdutoId.isNotEmpty &&
          regraProdutoId == normalizedProdutoId;
      if (regraProdutoId.isNotEmpty && !matchedByProduto) {
        continue;
      }

      final regraTaxGroupId = (regra.taxGroupId ?? '').trim().toLowerCase();
      final matchedByTaxGroup =
          regraTaxGroupId.isNotEmpty &&
          normalizedTaxGroupId.isNotEmpty &&
          regraTaxGroupId == normalizedTaxGroupId;
      if (regraTaxGroupId.isNotEmpty && !matchedByTaxGroup) {
        continue;
      }

      final regraNcm = _normalizeNcm(regra.ncm);
      final matchedByNcm = regraNcm.isNotEmpty && regraNcm == normalizedNcm;
      if (regraNcm.isNotEmpty && !matchedByNcm) {
        continue;
      }

      final regraCest = _normalizeCest(regra.cest);
      final matchedByCest =
          regraCest.isNotEmpty &&
          normalizedCest.isNotEmpty &&
          regraCest == normalizedCest;
      if (regraCest.isNotEmpty && !matchedByCest) {
        continue;
      }

      // Filtro de regime tributario do comprador (MVA ajustado p/ Simples
      // Nacional em UFs que concedem esse beneficio). Quando a regra define
      // esse criterio, ele e obrigatorio para a regra ser candidata.
      final regraBuyerRegime = (regra.applicableBuyerTaxRegime ?? '')
          .trim()
          .toLowerCase();
      final matchedByBuyerRegime =
          regraBuyerRegime.isNotEmpty && regraBuyerRegime == normalizedBuyerRegime;
      if (regraBuyerRegime.isNotEmpty && !matchedByBuyerRegime) {
        continue;
      }

      final isGenericRule =
          regraProdutoId.isEmpty &&
          regraTaxGroupId.isEmpty &&
          regraNcm.isEmpty;

      final tier = matchedByProduto
          ? 0
          : matchedByTaxGroup
              ? 1
              : matchedByNcm
                  ? 2
                  : (isGenericRule ? 3 : -1);
      if (tier < 0) {
        // Segurança: nenhum nivel tecnico reconhecido (nao deveria ocorrer
        // dado os 'continue' acima), descarta candidato ambiguo.
        continue;
      }

      candidates.add(
        _TaxRuleMatch(
          regra: regra,
          tier: tier,
          matchedByCest: matchedByCest,
          matchedByBuyerRegime: matchedByBuyerRegime,
        ),
      );
    }

    candidates.sort((a, b) {
      if (a.tier != b.tier) {
        return a.tier.compareTo(b.tier);
      }
      if (a.matchedByBuyerRegime != b.matchedByBuyerRegime) {
        return b.matchedByBuyerRegime ? 1 : -1;
      }
      if (a.matchedByCest != b.matchedByCest) {
        return b.matchedByCest ? 1 : -1;
      }
      return b.regra.priority.compareTo(a.regra.priority);
    });

    return candidates.isEmpty ? null : candidates.first;
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
    required double valorLiquidoItem,
    required double valorIpiItem,
    required double precoUnitario,
    required double quantidade,
    required double? precoConsiderado,
    required double mvaIva,
    required double reductionFactor,
    required double? baseCalculoPmc,
  }) {
    if (!isMva) {
      if (baseCalculoPmc != null && baseCalculoPmc > 0) {
        return baseCalculoPmc * quantidade;
      }
      return valorLiquidoItem;
    }

    final precoReferenciaUnitario =
        precoConsiderado != null && precoConsiderado > 0
        ? precoConsiderado
        : precoUnitario;

    // Base ST inclui o IPI do item (ver
    // docs/tributacao_motor_especificacao_tecnica.md secao 5c), independente
    // do perfil de operacao incluir ou nao o IPI na base do ICMS proprio.
    final baseBruta =
        (precoReferenciaUnitario * quantidade + valorIpiItem) *
        (1 + (mvaIva / 100));
    return baseBruta * reductionFactor;
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

  Future<List<TaxOperationProfile>> _loadTaxOperationProfiles(
    String tenantId,
  ) async {
    final repository = taxOperationProfileRepository;
    if (repository == null) {
      return const <TaxOperationProfile>[];
    }

    final cached = _taxOperationProfilesCache[tenantId];
    if (cached != null) {
      return cached;
    }

    final loaded = await repository.fetchAll(tenantId: tenantId);
    _taxOperationProfilesCache[tenantId] =
        List<TaxOperationProfile>.unmodifiable(loaded);
    return loaded;
  }
}
