import 'package:daily_order/domain/entities/items_tracker_column_filter.dart';
import 'package:daily_order/domain/entities/items_tracker_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final blank = ItemsTrackerRecord.fromMap({'id': 'blank'});
  final record = ItemsTrackerRecord.fromMap({
    'id': 'item',
    'unit_cost_snapshot': 12.5,
    'required_qty': 25,
    'inventory_note': 'Return stock',
    'follow_up_role': 'category',
    'latest_activity_body': 'Supplier accepted',
    'latest_activity_by_name': 'Doaa',
    'latest_comment': 'Call tomorrow',
    'comment_by_name': 'Sarah',
  });
  test('numeric ranges include boundaries and exclude blanks', () {
    final filter = ItemsTrackerColumnFilter(minimum: 12.5, maximum: 12.5);
    expect(filter.matches(ItemsTrackerColumn.cost, record), isTrue);
    expect(filter.matches(ItemsTrackerColumn.cost, blank), isFalse);
    expect(
      ItemsTrackerColumnFilter(
        maximum: 24,
      ).matches(ItemsTrackerColumn.quantity, record),
      isFalse,
    );
  });
  test('all, no values and blanks have distinct meanings', () {
    expect(
      ItemsTrackerColumnFilter().matches(ItemsTrackerColumn.cost, blank),
      isTrue,
    );
    expect(
      ItemsTrackerColumnFilter(
        selected: {},
      ).matches(ItemsTrackerColumn.reason, blank),
      isFalse,
    );
    final blanks = ItemsTrackerColumnFilter(selected: {''});
    expect(blanks.matches(ItemsTrackerColumn.reason, blank), isTrue);
    expect(blanks.matches(ItemsTrackerColumn.reason, record), isFalse);
  });
  test(
    'filters use visible actor and comment text, creation is blank action',
    () {
      expect(ItemsTrackerColumn.actionBy.value(record), 'Doaa');
      expect(ItemsTrackerColumn.commentBy.value(record), 'Sarah');
      expect(ItemsTrackerColumn.followUpBy.value(record), 'Category');
      final created = ItemsTrackerRecord.fromMap({
        'latest_activity_body': 'Follow-up: Created ->',
        'latest_activity_by_name': 'User',
      });
      expect(ItemsTrackerColumn.action.value(created), isEmpty);
      expect(ItemsTrackerColumn.actionBy.value(created), isEmpty);
    },
  );
}
