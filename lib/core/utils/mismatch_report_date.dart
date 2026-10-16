import 'dart:convert';

const _dubaiOffset = Duration(hours: 4);

/// Database log timestamps have no offset and use Asia/Dubai. Return UTC so
/// comparisons with created_at (timestamptz) also work near midnight.
DateTime? mismatchTimestamp(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  if (parsed.isUtc) {
    return parsed.toUtc();
  }
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  ).subtract(_dubaiOffset);
}

String mismatchDateLabel(DateTime? date) {
  if (date == null) return '—';
  final local = date.toUtc().add(_dubaiOffset);
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

/// Keep raw branch identities and ignore edits belonging to a deleted, older
/// record for the same branch/item. update_date is not maintained on edits.
List<Map<String, dynamic>> mismatchReportRows(
  List<Map<String, dynamic>> rows,
  List<Map<String, dynamic>> activity,
) {
  String key(Map<String, dynamic> row) =>
      jsonEncode([row['branch_name'], row['item_code']]);
  final latestUpdates = <String, DateTime>{};
  final history = <String>{};
  for (final log in activity) {
    final action = log['action'];
    if (action != 'update' && action != 'delete') continue;
    final identity = key(log);
    history.add(identity);
    if (action != 'update') continue;
    final changed = mismatchTimestamp(log['changed_at']);
    if (changed == null) continue;
    final previous = latestUpdates[identity];
    if (previous == null || changed.isAfter(previous)) {
      latestUpdates[identity] = changed;
    }
  }
  return rows.map((row) {
    final identity = key(row);
    final created =
        mismatchTimestamp(row['created_at']) ??
        mismatchTimestamp(row['update_date']);
    final changed = latestUpdates[identity];
    final date =
        changed != null && (created == null || !changed.isBefore(created))
        ? changed
        : created;
    return <String, dynamic>{
      ...row,
      'report_date': date?.toIso8601String(),
      'has_history': history.contains(identity),
    };
  }).toList();
}
