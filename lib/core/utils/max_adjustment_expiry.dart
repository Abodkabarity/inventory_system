/// Mirrors public.move_expired_max_adj: branch rows use 30/45 days;
/// other sources may override that deadline with end_date.
/// All calculations use calendar dates in the database timezone, Asia/Dubai.
class MaxAdjustmentExpiry {
  MaxAdjustmentExpiry(Map<String, dynamic> row, {DateTime? now}) {
    final type = (row['adjustment_type'] ?? '').toString().trim().toUpperCase();
    final duration = switch (type) {
      'INCREASE' => 30,
      'DECREASE' => 45,
      _ => null,
    };
    final explicit = (row['end_date'] ?? '').toString().trim();
    final branch = row['added_by'] == 'branch';
    hasIgnoredEndDate = branch && explicit.isNotEmpty;
    usesEndDate = !branch && explicit.isNotEmpty;
    deadline = duration == null
        ? null
        : usesEndDate
        ? parseDate(explicit)
        : parseDate(row['update_date'])?.add(Duration(days: duration));
    final dubai = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 4));
    final today = DateTime.utc(dubai.year, dubai.month, dubai.day);
    daysRemaining = deadline?.difference(today).inDays;
    basis = usesEndDate
        ? 'Custom end date'
        : '$type: $duration days from update date';
  }

  late final DateTime? deadline;
  late final int? daysRemaining;
  late final bool usesEndDate;
  late final bool hasIgnoredEndDate;
  late final String basis;

  String get label => labelForDays(daysRemaining);

  static String labelForDays(int? days) {
    if (days == null) return 'Unknown expiry';
    if (days < 0) return 'Expired ${-days} ${days == -1 ? 'day' : 'days'} ago';
    if (days == 0) return 'Ends today';
    return '$days ${days == 1 ? 'day' : 'days'} left';
  }

  String get dateLabel => deadline == null
      ? 'Unknown expiry'
      : '${deadline!.year.toString().padLeft(4, '0')}-'
            '${deadline!.month.toString().padLeft(2, '0')}-'
            '${deadline!.day.toString().padLeft(2, '0')}';

  String get tooltip => [
    '$basis. Expiry date: $dateLabel (Dubai).',
    'Expired records are archived by the daily server job.',
    if (hasIgnoredEndDate)
      'The server ignores end_date for adjustments added by branch.',
  ].join('\n');

  static DateTime? parseDate(Object? value) {
    final text = value?.toString().trim() ?? '';
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|T| )').firstMatch(text);
    final legacy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (iso == null && legacy == null) return null;
    final year = int.parse(iso?[1] ?? legacy![3]!);
    final month = int.parse(iso?[2] ?? legacy![2]!);
    final day = int.parse(iso?[3] ?? legacy![1]!);
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }
}
