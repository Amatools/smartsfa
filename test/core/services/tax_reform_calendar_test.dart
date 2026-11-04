import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/core/services/tax_reform_calendar.dart';

void main() {
  group('TaxReformCalendar.phaseForYear', () {
    test('returns naoIniciada before 2026', () {
      expect(TaxReformCalendar.phaseForYear(2025), TaxReformPhase.naoIniciada);
    });

    test('returns testeCbsIbs for 2026', () {
      expect(TaxReformCalendar.phaseForYear(2026), TaxReformPhase.testeCbsIbs);
    });

    test('returns transicao for 2027-2032', () {
      expect(TaxReformCalendar.phaseForYear(2027), TaxReformPhase.transicao);
      expect(TaxReformCalendar.phaseForYear(2032), TaxReformPhase.transicao);
    });

    test('returns implantacaoPlena from 2033 onward', () {
      expect(
        TaxReformCalendar.phaseForYear(2033),
        TaxReformPhase.implantacaoPlena,
      );
      expect(
        TaxReformCalendar.phaseForYear(2040),
        TaxReformPhase.implantacaoPlena,
      );
    });
  });

  group('TaxReformCalendar.impactsFinalPrice', () {
    test('remains false regardless of year (deliberate design)', () {
      expect(
        TaxReformCalendar.impactsFinalPrice(now: DateTime(2033, 6, 1)),
        isFalse,
      );
    });
  });

  group('TaxReformCalendar.oldTaxWeightPercentForYear/newTaxWeightPercentForYear', () {
    test('old tax is 100% before 2029', () {
      expect(TaxReformCalendar.oldTaxWeightPercentForYear(2026), 100);
      expect(TaxReformCalendar.oldTaxWeightPercentForYear(2028), 100);
      expect(TaxReformCalendar.newTaxWeightPercentForYear(2028), 0);
    });

    test('decreases 10 points per year from 2029 to 2032', () {
      expect(TaxReformCalendar.oldTaxWeightPercentForYear(2029), 90);
      expect(TaxReformCalendar.oldTaxWeightPercentForYear(2030), 80);
      expect(TaxReformCalendar.oldTaxWeightPercentForYear(2031), 70);
      expect(TaxReformCalendar.oldTaxWeightPercentForYear(2032), 60);
    });

    test('new tax weight is always the complement of old tax weight', () {
      for (final year in [2026, 2029, 2030, 2031, 2032, 2033, 2040]) {
        expect(
          TaxReformCalendar.oldTaxWeightPercentForYear(year) +
              TaxReformCalendar.newTaxWeightPercentForYear(year),
          100,
        );
      }
    });

    test('old tax is fully extinct from 2033 onward', () {
      expect(TaxReformCalendar.oldTaxWeightPercentForYear(2033), 0);
      expect(TaxReformCalendar.newTaxWeightPercentForYear(2033), 100);
      expect(TaxReformCalendar.oldTaxWeightPercentForYear(2040), 0);
    });
  });

  group('TaxReformCalendar.impostoSeletivoActiveForYear', () {
    test('is not active before 2027', () {
      expect(TaxReformCalendar.impostoSeletivoActiveForYear(2026), isFalse);
    });

    test('is active from 2027 onward', () {
      expect(TaxReformCalendar.impostoSeletivoActiveForYear(2027), isTrue);
      expect(TaxReformCalendar.impostoSeletivoActiveForYear(2033), isTrue);
    });
  });

  group('TaxReformCalendar.blendOldAndNewTaxValues', () {
    test('returns full old value before 2029', () {
      final blended = TaxReformCalendar.blendOldAndNewTaxValues(
        oldTaxFullValue: 100,
        newTaxFullValue: 80,
        year: 2027,
      );
      expect(blended, 100);
    });

    test('splits proportionally during transition (2030 = 80/20)', () {
      final blended = TaxReformCalendar.blendOldAndNewTaxValues(
        oldTaxFullValue: 100,
        newTaxFullValue: 50,
        year: 2030,
      );
      // 80% de 100 + 20% de 50 = 80 + 10 = 90.
      expect(blended, 90);
    });

    test('returns full new value from 2033 onward', () {
      final blended = TaxReformCalendar.blendOldAndNewTaxValues(
        oldTaxFullValue: 100,
        newTaxFullValue: 42,
        year: 2033,
      );
      expect(blended, 42);
    });
  });
}
