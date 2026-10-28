import '../../../core/models/domain_types.dart';
import '../../../core/models/tax_operation_profile.dart';

class TaxOperationProfileResolution {
  const TaxOperationProfileResolution({
    required this.profileKey,
    required this.calculateIcmsSt,
    required this.calculateDifal,
    required this.includeIpiInIcmsBase,
    required this.addIpiToTotal,
    required this.reduceIcmsForZfm,
    this.profileSource = 'native',
    this.overrideId,
  });

  final TaxOperationProfileKey profileKey;
  final bool calculateIcmsSt;
  final bool calculateDifal;
  final bool includeIpiInIcmsBase;
  final bool addIpiToTotal;
  final bool reduceIcmsForZfm;

  /// Origem da resolucao: 'native' (mapa `_nativeDefaults`) ou 'override'
  /// (veio de um documento ativo em `tax_operation_profiles`). Usado pela
  /// tela de auditoria fiscal para explicar a decisao (ver P1.4).
  final String profileSource;

  /// Id do `TaxOperationProfile` usado, quando `profileSource == 'override'`.
  final String? overrideId;
}

class TaxOperationClassifierService {
  const TaxOperationClassifierService();

  static const Map<TaxOperationProfileKey, TaxOperationProfileResolution>
  _nativeDefaults = <TaxOperationProfileKey, TaxOperationProfileResolution>{
    TaxOperationProfileKey.revendaSameUf: TaxOperationProfileResolution(
      profileKey: TaxOperationProfileKey.revendaSameUf,
      calculateIcmsSt: true,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    TaxOperationProfileKey.revendaInterstate: TaxOperationProfileResolution(
      profileKey: TaxOperationProfileKey.revendaInterstate,
      calculateIcmsSt: true,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    TaxOperationProfileKey.usoConsumoContribuinteSameUf:
        TaxOperationProfileResolution(
          profileKey: TaxOperationProfileKey.usoConsumoContribuinteSameUf,
          calculateIcmsSt: false,
          calculateDifal: false,
          includeIpiInIcmsBase: true,
          addIpiToTotal: true,
          reduceIcmsForZfm: false,
        ),
    TaxOperationProfileKey.usoConsumoContribuinteInterstate:
        TaxOperationProfileResolution(
          profileKey: TaxOperationProfileKey.usoConsumoContribuinteInterstate,
          calculateIcmsSt: false,
          calculateDifal: true,
          includeIpiInIcmsBase: true,
          addIpiToTotal: true,
          reduceIcmsForZfm: false,
        ),
    TaxOperationProfileKey.usoConsumoNaoContribuinteSameUf:
        TaxOperationProfileResolution(
          profileKey: TaxOperationProfileKey.usoConsumoNaoContribuinteSameUf,
          calculateIcmsSt: false,
          calculateDifal: false,
          includeIpiInIcmsBase: true,
          addIpiToTotal: true,
          reduceIcmsForZfm: false,
        ),
    TaxOperationProfileKey.usoConsumoNaoContribuinteInterstate:
        TaxOperationProfileResolution(
          profileKey: TaxOperationProfileKey
              .usoConsumoNaoContribuinteInterstate,
          calculateIcmsSt: false,
          calculateDifal: true,
          includeIpiInIcmsBase: true,
          addIpiToTotal: true,
          reduceIcmsForZfm: false,
        ),
    TaxOperationProfileKey.industrializacaoSameUf: TaxOperationProfileResolution(
      profileKey: TaxOperationProfileKey.industrializacaoSameUf,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: true,
      reduceIcmsForZfm: false,
    ),
    TaxOperationProfileKey.industrializacaoInterstate:
        TaxOperationProfileResolution(
          profileKey: TaxOperationProfileKey.industrializacaoInterstate,
          calculateIcmsSt: false,
          calculateDifal: false,
          includeIpiInIcmsBase: false,
          addIpiToTotal: true,
          reduceIcmsForZfm: false,
        ),
    TaxOperationProfileKey.zfmIndustrializacao: TaxOperationProfileResolution(
      profileKey: TaxOperationProfileKey.zfmIndustrializacao,
      calculateIcmsSt: false,
      calculateDifal: false,
      includeIpiInIcmsBase: false,
      addIpiToTotal: false,
      reduceIcmsForZfm: true,
    ),
    TaxOperationProfileKey.zfmComercializacaoRevenda:
        TaxOperationProfileResolution(
          profileKey: TaxOperationProfileKey.zfmComercializacaoRevenda,
          calculateIcmsSt: false,
          calculateDifal: false,
          includeIpiInIcmsBase: false,
          addIpiToTotal: false,
          reduceIcmsForZfm: true,
        ),
  };

  TaxOperationProfileResolution classify({
    required SalePurpose salePurpose,
    required bool sameUf,
    required CustomerTaxProfile customerTaxProfile,
    required bool isZonaFrancaSuframa,
    List<TaxOperationProfile> overrides = const <TaxOperationProfile>[],
    String? representedCompanyId,
  }) {
    final profileKey = _resolveKey(
      salePurpose: salePurpose,
      sameUf: sameUf,
      customerTaxProfile: customerTaxProfile,
      isZonaFrancaSuframa: isZonaFrancaSuframa,
    );

    final nativeDefault = _nativeDefaults[profileKey] ??
        _nativeDefaults[TaxOperationProfileKey.revendaSameUf]!;

    final override = _resolveOverride(
      overrides: overrides,
      profileKey: profileKey,
      representedCompanyId: representedCompanyId,
    );
    if (override == null) {
      return nativeDefault;
    }

    return TaxOperationProfileResolution(
      profileKey: profileKey,
      calculateIcmsSt: override.calculateIcmsSt,
      calculateDifal: override.calculateDifal,
      includeIpiInIcmsBase: override.includeIpiInIcmsBase,
      addIpiToTotal: override.addIpiToTotal,
      reduceIcmsForZfm: override.reduceIcmsForZfm,
      profileSource: 'override',
      overrideId: override.id,
    );
  }

  /// Resolve o override dinamico de um perfil, se existir.
  ///
  /// Prioriza um override escopado para a `representedCompanyId` informada;
  /// na ausencia dele, usa um override global (sem representada definida).
  /// Overrides inativos ou de outro `profileKey` sao ignorados.
  TaxOperationProfile? _resolveOverride({
    required List<TaxOperationProfile> overrides,
    required TaxOperationProfileKey profileKey,
    required String? representedCompanyId,
  }) {
    if (overrides.isEmpty) {
      return null;
    }
    final normalizedScope = (representedCompanyId ?? '').trim();
    TaxOperationProfile? scoped;
    TaxOperationProfile? global;
    for (final profile in overrides) {
      if (!profile.isActive || profile.profileKey != profileKey.value) {
        continue;
      }
      final profileScope = (profile.representedCompanyId ?? '').trim();
      if (profileScope.isEmpty) {
        global ??= profile;
      } else if (normalizedScope.isNotEmpty && profileScope == normalizedScope) {
        scoped ??= profile;
      }
    }
    return scoped ?? global;
  }

  TaxOperationProfileKey _resolveKey({
    required SalePurpose salePurpose,
    required bool sameUf,
    required CustomerTaxProfile customerTaxProfile,
    required bool isZonaFrancaSuframa,
  }) {
    if (isZonaFrancaSuframa) {
      if (salePurpose == SalePurpose.industrializacao) {
        return TaxOperationProfileKey.zfmIndustrializacao;
      }
      return TaxOperationProfileKey.zfmComercializacaoRevenda;
    }

    switch (salePurpose) {
      case SalePurpose.revenda:
        return sameUf
            ? TaxOperationProfileKey.revendaSameUf
            : TaxOperationProfileKey.revendaInterstate;
      case SalePurpose.usoConsumo:
        if (customerTaxProfile == CustomerTaxProfile.contribuinte) {
          return sameUf
              ? TaxOperationProfileKey.usoConsumoContribuinteSameUf
              : TaxOperationProfileKey.usoConsumoContribuinteInterstate;
        }
        return sameUf
            ? TaxOperationProfileKey.usoConsumoNaoContribuinteSameUf
            : TaxOperationProfileKey.usoConsumoNaoContribuinteInterstate;
      case SalePurpose.industrializacao:
        return sameUf
            ? TaxOperationProfileKey.industrializacaoSameUf
            : TaxOperationProfileKey.industrializacaoInterstate;
    }
  }
}
