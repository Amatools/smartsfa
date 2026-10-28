import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/features/precos/services/tax_rounding_policy.dart';

void main() {
  group('TaxRoundingPolicy', () {
    test('rounds half up instead of bankers rounding', () {
      // Dart's default double.toStringAsFixed uses round-half-to-even in
      // some cases; the fiscal policy must always round half up.
      expect(TaxRoundingPolicy.round(0.5, decimals: 0), 1);
      expect(TaxRoundingPolicy.round(1.5, decimals: 0), 2);
      expect(TaxRoundingPolicy.round(2.5, decimals: 0), 3);
    });

    test('handles the classic 2.675 floating point edge case', () {
      // 2.675 is represented internally as 2.67499999999999982236431605997...
      // Naive rounding (value*100+0.5).floor()/100 yields 2.67 instead of 2.68.
      expect(TaxRoundingPolicy.round(2.675, decimals: 2), 2.68);
    });

    test('rounds negative values symmetrically', () {
      expect(TaxRoundingPolicy.round(-2.675, decimals: 2), -2.68);
      expect(TaxRoundingPolicy.round(-1.5, decimals: 0), -2);
    });

    test('roundCurrency rounds to 2 decimals', () {
      expect(TaxRoundingPolicy.roundCurrency(10.005), 10.01);
      expect(TaxRoundingPolicy.roundCurrency(10.0), 10.0);
    });

    test('returns 0 for NaN or infinite values', () {
      expect(TaxRoundingPolicy.round(double.nan), 0);
      expect(TaxRoundingPolicy.round(double.infinity), 0);
    });
  });
}
