import 'max_adjustment_expiry.dart';
import 'store_branch_identity_registry.dart';

/// Display rows only: database/import identities remain unchanged.
List<Map<String, dynamic>> maxAdjExportRows(
  List<Map<String, dynamic>> rows, {
  DateTime? now,
}) {
  final snapshot = now ?? DateTime.now();
  return rows.map((row) {
    final expiry = MaxAdjustmentExpiry(row, now: snapshot);
    final historical = row['moved_at'] != null || row['action_type'] != null;
    return <String, dynamic>{
      for (final entry in row.entries)
        entry.key: StoreBranchIdentityRegistry.exportValue(
          entry.key,
          entry.value,
        ),
      'expiry_date': expiry.deadline == null ? '' : expiry.dateLabel,
      'remaining_days': historical
          ? 'Historical record'
          : expiry.daysRemaining ?? 'Unknown expiry',
    };
  }).toList();
}
