import 'package:flutter_test/flutter_test.dart';
import 'package:smartsfa/src/shared/domain/date_time_label.dart';

void main() {
  test('formats date-time with zero padding', () {
    final value = DateTime(2026, 1, 2, 3, 4);

    final label = formatDateTimeLabel(value);

    expect(label, '02/01/2026 03:04');
  });
}
