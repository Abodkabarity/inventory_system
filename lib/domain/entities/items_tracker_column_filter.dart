import 'items_tracker_record.dart';

enum ItemsTrackerColumn {
  product('PRODUCT'),
  cost('COST'),
  quantity('QUANTITY'),
  reason('REASON'),
  action('ACTION'),
  actionBy('ACTION BY'),
  comment('COMMENT'),
  commentBy('COMMENT BY'),
  followUpBy('FOLLOW UP BY');

  final String label;
  const ItemsTrackerColumn(this.label);
  bool get isNumeric => this == cost || this == quantity;

  double? number(ItemsTrackerRecord record) => switch (this) {
    cost => record.unitCost,
    quantity => record.requiredQty,
    _ => null,
  };

  String value(ItemsTrackerRecord record) {
    final initial =
        record.displayedLastActivity.isEmpty ||
        RegExp(
          r'^Follow-up:\s*Created\s*->\s*$',
          caseSensitive: false,
        ).hasMatch(record.displayedLastActivity);
    return switch (this) {
      product => record.itemName.trim(),
      cost => record.unitCost?.toString() ?? '',
      quantity => record.requiredQty.toString(),
      reason => record.inventoryNote.trim(),
      action => initial ? '' : record.displayedLastActivity,
      actionBy =>
        initial
            ? ''
            : record.displayedLastActivityByName.isNotEmpty
            ? record.displayedLastActivityByName
            : record.displayedLastActivityRole.isNotEmpty
            ? ItemsTrackerRoles.label(record.displayedLastActivityRole)
            : '',
      comment => record.latestComment.trim(),
      commentBy =>
        record.latestComment.trim().isEmpty
            ? ''
            : record.commentByName.trim().isNotEmpty
            ? record.commentByName.trim()
            : record.commentByRole.trim().isNotEmpty
            ? ItemsTrackerRoles.label(record.commentByRole)
            : '',
      followUpBy => ItemsTrackerRoles.label(record.followUpRole),
    };
  }
}

/// Null selection means all values, while an empty set means no values.
class ItemsTrackerColumnFilter {
  final Set<String>? selected;
  final double? minimum;
  final double? maximum;
  ItemsTrackerColumnFilter({Set<String>? selected, this.minimum, this.maximum})
    : selected = selected == null ? null : Set.unmodifiable(selected);

  bool get isActive => selected != null || minimum != null || maximum != null;
  bool matches(ItemsTrackerColumn column, ItemsTrackerRecord record) {
    if (selected != null && !selected!.contains(column.value(record))) {
      return false;
    }
    if (minimum != null || maximum != null) {
      final number = column.number(record);
      if (number == null) return false;
      if (minimum != null && number < minimum!) return false;
      if (maximum != null && number > maximum!) return false;
    }
    return true;
  }
}
