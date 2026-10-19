import 'package:intl/intl.dart';

/// Item Report timestamps represent instants in Dubai; date-only payloads are
/// already calendar dates and must not shift with the device's timezone.
DateTime? stockItemAddedDate(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  final parsed = value is DateTime ? value : DateTime.tryParse(raw);
  if (parsed == null) return null;
  final dubai = parsed.isUtc ? parsed.add(const Duration(hours: 4)) : parsed;
  return DateTime(dubai.year, dubai.month, dubai.day);
}

String formatStockItemAddedDate(dynamic value, {String empty = '—'}) {
  final date = stockItemAddedDate(value);
  return date == null ? empty : DateFormat('dd/MM/yyyy').format(date);
}
