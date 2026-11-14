/// Compact date used by corpus cards.
///
/// Shows `2026.09.12` for earlier years and `09.12` for the current year.
String formatCorpusDate(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  if (date.year == current.year) return '$month.$day';
  return '${date.year.toString().padLeft(4, '0')}.$month.$day';
}
