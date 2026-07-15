import 'package:daily_order/domain/entities/purchase_status_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('purchase record maps its joined status', () {
    final record = PurchaseStatusRecord.fromMap({
      'id': 7,
      'item_code': 'ABC-1',
      'item_name': 'Example item',
      'status_id': 3,
      'status_date': '2026-07-14',
      'purchase_status_options': {'name': 'AVAILABLE'},
    });

    expect(record.itemCode, 'ABC-1');
    expect(record.statusName, 'AVAILABLE');
    expect(record.statusDate, DateTime(2026, 7, 14));
  });
}
