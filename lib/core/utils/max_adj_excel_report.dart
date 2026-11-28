import 'max_adjustment_expiry.dart';
import 'store_branch_identity_registry.dart';

/// Lazy typed values for the background Excel writer. Never copy the complete
/// history into a second list of display maps on the browser's UI thread.
class MaxAdjExcelReport {
  MaxAdjExcelReport(this.rows, {required bool includeHistory, DateTime? now})
    : snapshot = now ?? DateTime.now(),
      keys = [
        'branch_name',
        'item_code',
        'item_name',
        'current_demand_30d',
        'max_adjustment_30d',
        'adjustment_type',
        'reason',
        'update_date',
        'qty',
        'added_by',
        'end_date',
        'expiry_date',
        'remaining_days',
        if (includeHistory) ...['created_at', 'action_type', 'moved_at'],
      ] {
    if (rows.length >= 1048576) {
      throw StateError('The report exceeds the Excel worksheet row limit.');
    }
  }

  final List<Map<String, dynamic>> rows;
  final DateTime snapshot;
  final List<String> keys;

  static const titles = {
    'branch_name': 'Branch',
    'item_code': 'Item Code',
    'item_name': 'Item Name',
    'current_demand_30d': 'Demand',
    'max_adjustment_30d': 'Max Adjustment',
    'adjustment_type': 'Type',
    'reason': 'Reason',
    'update_date': 'Update Date',
    'qty': 'Qty',
    'added_by': 'Added By',
    'end_date': 'End Date',
    'expiry_date': 'Effective Expiry Date',
    'remaining_days': 'Days Remaining (at export)',
    'created_at': 'Created At',
    'action_type': 'Action Type',
    'moved_at': 'Moved At',
  };
  static const _dates = {'update_date', 'end_date', 'expiry_date'};
  static const _numbers = {
    'current_demand_30d',
    'max_adjustment_30d',
    'qty',
    'remaining_days',
  };

  List<String> get headers => keys.map((key) => titles[key]!).toList();
  List<String> get types => [
    for (final key in keys)
      _dates.contains(key)
          ? 'date'
          : _numbers.contains(key)
          ? 'number'
          : 'text',
  ];
  List<int> get widths => [
    for (final key in keys)
      key.contains('name')
          ? 35
          : key.contains('reason')
          ? 40
          : key.contains('date') || key.endsWith('_at') || key.contains('code')
          ? 25
          : 20,
  ];

  Iterable<List<Object>> get values sync* {
    for (final row in rows) {
      final expiry = MaxAdjustmentExpiry(row, now: snapshot);
      final historical = row['moved_at'] != null || row['action_type'] != null;
      yield [
        for (final key in keys)
          _value(key, switch (key) {
            'expiry_date' => expiry.deadline == null ? '' : expiry.dateLabel,
            'remaining_days' =>
              historical
                  ? 'Historical record'
                  : expiry.daysRemaining ?? 'Unknown expiry',
            _ => row[key],
          }),
      ];
    }
  }

  Object _value(String key, Object? raw) {
    final value = StoreBranchIdentityRegistry.exportValue(key, raw);
    if (value == null) return '';
    if (_dates.contains(key)) {
      return MaxAdjustmentExpiry.parseDate(value)?.toIso8601String() ??
          value.toString();
    }
    if (value is num) return value.isFinite ? value : '';
    return value.toString();
  }
}
