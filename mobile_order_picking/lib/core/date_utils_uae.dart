import 'package:intl/intl.dart';

DateTime nowUae() {
  return DateTime.now().toUtc().add(const Duration(hours: 4));
}

DateTime todayUae() {
  final now = nowUae();
  return DateTime(now.year, now.month, now.day);
}

DateTime operationalDateUae() {
  final now = nowUae();
  final today = DateTime(now.year, now.month, now.day);
  if (now.hour >= 21) {
    return today.add(const Duration(days: 1));
  }
  return today;
}

String ymd(DateTime date) {
  return DateFormat('yyyy-MM-dd').format(date);
}

String displayDate(DateTime date) {
  return DateFormat('dd-MM-yyyy').format(date);
}
