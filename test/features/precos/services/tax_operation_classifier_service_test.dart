import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/core/models/domain_types.dart';
import 'package:smartsfa/src/features/precos/services/tax_operation_classifier_service.dart';

void main() {
  group('TaxOperationClassifierService', () {
    const service = TaxOperationClassifierService();

    test('classifies revenda same UF with ST enabled', () {
      final resolution = service.classify(
        salePurpose: SalePurpose.revenda,
        sameUf: true,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        isZonaFrancaSuframa: false,
      );

      expect(resolution.profileKey, TaxOperationProfileKey.revendaSameUf);
      expect(resolution.calculateIcmsSt, isTrue);
      expect(resolution.calculateDifal, isFalse);
      expect(resolution.addIpiToTotal, isTrue);
    });

    test('classifies uso/consumo interstate nao contribuinte with DIFAL', () {
      final resolution = service.classify(
        salePurpose: SalePurpose.usoConsumo,
        sameUf: false,
        customerTaxProfile: CustomerTaxProfile.naoContribuinte,
        isZonaFrancaSuframa: false,
      );

      expect(
        resolution.profileKey,
        TaxOperationProfileKey.usoConsumoNaoContribuinteInterstate,
      );
      expect(resolution.calculateIcmsSt, isFalse);
      expect(resolution.calculateDifal, isTrue);
      expect(resolution.includeIpiInIcmsBase, isTrue);
    });

    test('classifies ZFM with ICMS discount and no IPI add-on', () {
      final resolution = service.classify(
        salePurpose: SalePurpose.industrializacao,
        sameUf: false,
        customerTaxProfile: CustomerTaxProfile.contribuinte,
        isZonaFrancaSuframa: true,
      );

      expect(
        resolution.profileKey,
        TaxOperationProfileKey.zfmIndustrializacao,
      );
      expect(resolution.reduceIcmsForZfm, isTrue);
      expect(resolution.calculateIcmsSt, isFalse);
      expect(resolution.calculateDifal, isFalse);
      expect(resolution.addIpiToTotal, isFalse);
    });
  });
}
