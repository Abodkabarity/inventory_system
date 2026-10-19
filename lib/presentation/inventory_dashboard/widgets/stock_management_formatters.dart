import 'package:intl/intl.dart';

final _percentage = NumberFormat('#,##0.##');

/// Formats the store-to-branches ratio for display without changing the raw
/// value used by sorting and filtering.
String formatStoreBranchesPercentage(num? ratio) {
  if (ratio == null) return '—';
  return '${_percentage.format(ratio * 100)}%';
}
