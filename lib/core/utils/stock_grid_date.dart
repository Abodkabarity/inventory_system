import 'package:intl/intl.dart';

/// A calendar day for a data-grid cell. It remains a [DateTime], so Syncfusion
/// retains chronological sorting and date filtering, while its popup displays
/// the same day-month-year label as the table cell.
class StockGridDate implements DateTime {
  StockGridDate(DateTime value)
    : _value = DateTime.utc(value.year, value.month, value.day);

  final DateTime _value;

  @override
  int get year => _value.year;
  @override
  int get month => _value.month;
  @override
  int get day => _value.day;
  @override
  int get hour => _value.hour;
  @override
  int get minute => _value.minute;
  @override
  int get second => _value.second;
  @override
  int get millisecond => _value.millisecond;
  @override
  int get microsecond => _value.microsecond;
  @override
  int get weekday => _value.weekday;
  @override
  int get millisecondsSinceEpoch => _value.millisecondsSinceEpoch;
  @override
  int get microsecondsSinceEpoch => _value.microsecondsSinceEpoch;
  @override
  bool get isUtc => _value.isUtc;
  @override
  String get timeZoneName => _value.timeZoneName;
  @override
  Duration get timeZoneOffset => _value.timeZoneOffset;

  @override
  DateTime add(Duration duration) => _value.add(duration);
  @override
  DateTime subtract(Duration duration) => _value.subtract(duration);
  @override
  int compareTo(DateTime other) => _value.compareTo(other);
  @override
  Duration difference(DateTime other) => _value.difference(other);
  @override
  bool isAfter(DateTime other) => _value.isAfter(other);
  @override
  bool isAtSameMomentAs(DateTime other) => _value.isAtSameMomentAs(other);
  @override
  bool isBefore(DateTime other) => _value.isBefore(other);
  @override
  DateTime toLocal() => _value.toLocal();
  @override
  String toIso8601String() => _value.toIso8601String();
  @override
  DateTime toUtc() => _value.toUtc();

  @override
  bool operator ==(Object other) =>
      other is DateTime && isAtSameMomentAs(other);
  @override
  int get hashCode => _value.hashCode;
  @override
  String toString() => DateFormat('dd/MM/yyyy').format(_value);
}

DateTime? stockGridDate(DateTime? value) =>
    value == null ? null : StockGridDate(value);
