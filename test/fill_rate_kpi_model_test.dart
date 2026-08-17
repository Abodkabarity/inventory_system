import 'package:daily_order/data/datasources/remote/fill_rate_kpi_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fill Rate KPI models', () {
    test('maps summary values returned as Postgres numeric strings', () {
      final summary = FillRateSummary.fromMap({
        'branch_name': 'ALL BRANCHES',
        'total_items': 10,
        'supplied_items': 7,
        'fully_supplied': 5,
        'partially_supplied': 2,
        'not_supplied': 3,
        'required_qty': '40',
        'supplied_qty': '30.5',
        'line_fill_rate': '65.25',
        'unit_fill_rate': '76.25',
      });

      expect(summary.totalItems, 10);
      expect(summary.partiallySupplied, 2);
      expect(summary.suppliedQty, 30.5);
      expect(summary.unitFillRate, 76.25);
    });

    test(
      'preserves edited effective quantity and capped supplied quantity',
      () {
        final item = FillRateItem.fromMap({
          'total_count': 1,
          'run_date': '2026-08-10',
          'branch_name': 'RAWDAH',
          'item_code': 'ITEM-1',
          'item_name': 'Example',
          'original_qty': '2',
          'required_qty': '1',
          'was_edited': true,
          'transferred_qty': '3',
          'supplied_qty': '1',
          'fill_rate': '100',
          'fulfillment_status': 'Fully Supplied',
          'purchase_status': 'AVAILABLE',
        });

        expect(item.wasEdited, isTrue);
        expect(item.originalQty, 2);
        expect(item.requiredQty, 1);
        expect(item.suppliedQty, 1);
        expect(item.fillRate, 100);
      },
    );

    test('applies the current canonical purchase status to a report row', () {
      final staleItem = FillRateItem.fromMap({
        'total_count': 905,
        'run_date': '2026-08-10',
        'branch_name': 'AL AIN MAIN',
        'item_code': '16-01-00275',
        'item_name': 'AMARYL 4 MG TAB 30 S',
        'original_qty': 6,
        'required_qty': 6,
        'was_edited': false,
        'transferred_qty': 1,
        'supplied_qty': 1,
        'fill_rate': 16.67,
        'fulfillment_status': 'Partially Supplied',
        'purchase_status': 'Not Assigned',
      });

      final currentItem = staleItem.withPurchaseStatus('AVAILABLE');

      expect(currentItem.itemCode, '16-01-00275');
      expect(currentItem.purchaseStatus, 'AVAILABLE');
      expect(currentItem.fulfillmentStatus, 'Partially Supplied');
      expect(currentItem.requiredQty, 6);
    });

    test('combines AVAILABLE variants and empty status in focused metrics', () {
      const statuses = [
        FillRateStatus(
          name: 'AVAILABLE',
          totalItems: 20,
          suppliedItems: 10,
          share: 40,
          lineFillRate: 50,
          unitFillRate: 60,
          requiredQty: 100,
          suppliedQty: 60,
        ),
        FillRateStatus(
          name: 'AVAILABLE N.E',
          totalItems: 10,
          suppliedItems: 5,
          share: 20,
          lineFillRate: 40,
          unitFillRate: 50,
          requiredQty: 50,
          suppliedQty: 25,
        ),
        FillRateStatus(
          name: 'Not Assigned',
          totalItems: 15,
          suppliedItems: 3,
          share: 30,
          lineFillRate: 20,
          unitFillRate: 20,
          requiredQty: 50,
          suppliedQty: 10,
        ),
        FillRateStatus(
          name: 'PENDING AGREEMENT',
          totalItems: 5,
          suppliedItems: 0,
          share: 10,
          lineFillRate: 0,
          unitFillRate: 0,
          requiredQty: 10,
          suppliedQty: 0,
        ),
      ];

      final focused = FillRateFocusedMetrics.fromStatuses(statuses);

      expect(focused.includedItems, 45);
      expect(focused.excludedItems, 5);
      expect(focused.requiredQty, 200);
      expect(focused.suppliedQty, 95);
      expect(focused.unitFillRate, 47.5);
      expect(focused.lineFillRate, closeTo(37.7778, 0.001));
    });
  });
}
