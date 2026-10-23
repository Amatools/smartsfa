import '../../../core/models/domain_types.dart';

class TaxOperationProfileResolution {
  const TaxOperationProfileResolution({
    required this.profileKey,
    required this.calculateIcmsSt,
    required this.calculateDifal,
    required this.includeIpiInIcmsBase,
    required this.addIpiToTotal,
    required this.reduceIcmsForZfm,
  });

  final TaxOperationProfileKey profileKey;
  final bool calculateIcmsSt;
  final bool calculateDifal;
  final bool includeIpiInIcmsBase;
  final bool addIpiToTotal;
  final bool reduceIcmsForZfm;
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
  }) {
    final profileKey = _resolveKey(
      salePurpose: salePurpose,
      sameUf: sameUf,
      customerTaxProfile: customerTaxProfile,
      isZonaFrancaSuframa: isZonaFrancaSuframa,
    );

    return _nativeDefaults[profileKey] ??
        _nativeDefaults[TaxOperationProfileKey.revendaSameUf]!;
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
