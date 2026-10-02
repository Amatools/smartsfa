import 'dart:math' as math;

import '../../../core/models/product_base_price.dart';
import '../../../core/models/tax_rule.dart';
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

  Future<ProductTaxCalculationResult> calcularTotaisItem({
    required String tenantId,
    required String produtoId,
    required String tabelaId,
    required String clienteUf,
    required double quantidade,
    String ufOrigem = 'SP',
  }) async {
    final normalizedTenantId = tenantId.trim();
    final normalizedProdutoId = produtoId.trim();
    final normalizedTabelaId = tabelaId.trim();
    final normalizedUfDestino = clienteUf.trim().toUpperCase();
    final normalizedUfOrigem = ufOrigem.trim().toUpperCase();

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

    final regras = await taxRuleRepository.fetchAll(
      tenantId: normalizedTenantId,
    );
    final regra = _resolveTaxRule(
      regras: regras,
      ncm: produto.ncm,
      cest: produto.cest,
      ufOrigem: normalizedUfOrigem,
      ufDestino: normalizedUfDestino,
    );

    final precoBase = precoBaseRegistro.basePrice * quantidade;
    final precoUnitario = precoBaseRegistro.basePrice;
    final aliquotaIpi = produto.aliquotaIpiBase ?? 0;
    final valorIpi = precoBase * (aliquotaIpi / 100);

    final aliquotaCredito = regra?.aliquotaCredito ?? regra?.aliquotaIcms ?? 0;
    final aliquotaDestino = regra?.aliquotaDestino ?? regra?.aliquotaSt ?? 0;
    final mvaIva = regra?.mvaIva ?? 0;
    final tipoSt = (regra?.stCalculationType ?? 'mva').trim().toLowerCase();
    final isMva = tipoSt != 'pmc';

    double valorSt = 0;
    if (aliquotaDestino > 0) {
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
      valorSt = math.max(icmsStCheio - icmsProprio, 0);
    }

    final aliquotaDifal = regra?.aliquotaDifal ?? 0;
    final valorDifal = precoBase * (aliquotaDifal / 100);

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
    final all = await basePriceRepository.fetchAll(tenantId: tenantId);
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
}
