import 'stock_management.dart';

enum StockSalesChannel {
  cash('cash', 'Cash'),
  online('online', 'Online'),
  insuranceBasic('insurance_basic', 'Insurance Basic'),
  insuranceThiqa('insurance_thiqa', 'Insurance Thiqa'),
  otherInsurance('other_insurance', 'Other Insurance');

  final String key, label;
  const StockSalesChannel(this.key, this.label);
}

class StockDailySalesDay {
  final DateTime date;
  final Map<StockSalesChannel, double> quantities;
  const StockDailySalesDay(this.date, this.quantities);
  double qty(StockSalesChannel channel) => quantities[channel] ?? 0;
  double get total => quantities.values.fold(0, (a, b) => a + b);
  String get isoDate => date.toIso8601String().substring(0, 10);
  Map<String, dynamic> get exportRow => {
    'Date': isoDate,
    for (final channel in StockSalesChannel.values) channel.label: qty(channel),
    'Total Qty': total,
  };
}

/// Calendar dates and quantities belong to the same stock snapshot as the KPIs.
class StockDailySalesMix {
  final List<StockDailySalesDay> days;
  final bool available;
  const StockDailySalesMix._(this.days, this.available);
  factory StockDailySalesMix.fromMap(Map<String, dynamic> item) {
    const unavailable = StockDailySalesMix._([], false);
    if (item['daily_sales_45d_available'] != true ||
        item['daily_sales_45d'] is! List) {
      return unavailable;
    }
    DateTime? date(Object? raw) {
      final value = DateTime.tryParse('$raw');
      return value == null
          ? null
          : DateTime.utc(value.year, value.month, value.day);
    }

    final meta = stockMap(item['meta']);
    final from = date(meta['demand_from']),
        through = date(meta['demand_through']);
    if (from == null ||
        through == null ||
        from.isAfter(through) ||
        through.difference(from).inDays >= 45) {
      return unavailable;
    }
    final raw = <DateTime, Map<String, dynamic>>{};
    for (final value in item['daily_sales_45d'] as List) {
      final row = stockMap(value), day = date(stockMap(value)['date']);
      if (day == null ||
          day.isBefore(from) ||
          day.isAfter(through) ||
          raw.containsKey(day)) {
        return unavailable;
      }
      for (final channel in StockSalesChannel.values) {
        final qty = num.tryParse('${row[channel.key]}');
        if (qty == null || !qty.isFinite) return unavailable;
      }
      raw[day] = row;
    }
    final days = [
      for (
        var day = from;
        !day.isAfter(through);
        day = day.add(const Duration(days: 1))
      )
        StockDailySalesDay(
          day,
          Map.unmodifiable({
            for (final channel in StockSalesChannel.values)
              channel: stockNumber(raw[day]?[channel.key]),
          }),
        ),
    ];
    final total = days.fold(0.0, (sum, day) => sum + day.total);
    final expected = stockNumber(item['recent_sales']);
    final tolerance = 0.000001 + expected.abs() * 0.000000001;
    if ((total - expected).abs() > tolerance) return unavailable;
    return StockDailySalesMix._(List.unmodifiable(days), true);
  }
  double totalFor(StockSalesChannel channel) =>
      days.fold(0, (sum, day) => sum + day.qty(channel));
  double get total => days.fold(0, (sum, day) => sum + day.total);
}
