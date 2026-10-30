import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/utils/date_format.dart';

void main() {
  test('current-year dates omit the year', () {
    expect(
      formatCorpusDate(DateTime(2026, 9, 12), now: DateTime(2026, 10, 29)),
      '09.12',
    );
  });

  test('other years keep the year', () {
    expect(
      formatCorpusDate(DateTime(2025, 1, 3), now: DateTime(2026, 10, 29)),
      '2025.01.03',
    );
  });
}
