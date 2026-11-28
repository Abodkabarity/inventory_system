import 'dart:convert';
import 'dart:io';

import 'package:daily_order/core/utils/max_adj_excel_report.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'worker rows preserve dates, codes, numeric Qty, history and branch labels',
    () {
      StoreBranchIdentityRegistry.groups.value = {
        'AL AIN': '71',
        'CITY': 'APG',
      };
      addTearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
      final original = {
        'branch_name': 'Al Ain',
        'item_code': '00123',
        'item_name': '=literal',
        'current_demand_30d': 0,
        'max_adjustment_30d': 2.5,
        'qty': 2.5,
        'adjustment_type': 'INCREASE',
        'update_date': '2026-11-01',
        'added_by': 'inventory',
        'end_date': null,
        'created_at': '2026-11-01T15:26:32+04:00',
      };
      final report = MaxAdjExcelReport(
        [
          original,
          {
            ...original,
            'branch_name': 'City',
            'action_type': 'UPDATE',
            'moved_at': '2026-11-20T10:12:35',
          },
        ],
        includeHistory: true,
        now: DateTime.utc(2026, 11, 26),
      );
      final values = report.values.toList();
      expect(values[0][0], '71 Al Ain');
      expect(values[1][0], 'City');
      expect(values[0][1], '00123');
      expect(values[0][3], 0);
      expect(values[0][4], 2.5);
      expect(values[0][7], '2026-11-01T00:00:00.000Z');
      expect(values[0][10], '');
      expect(values[0][11], '2026-12-01T00:00:00.000Z');
      expect(values[0][12], 5);
      expect(values[1][12], 'Historical record');
      expect(values[0][13], original['created_at']);
      expect(values[1][15], '2026-11-20T10:12:35');
      expect(original['branch_name'], 'Al Ain');
      expect(original.containsKey('expiry_date'), false);
      expect(report.headers.length, 16);
      expect(MaxAdjExcelReport([], includeHistory: false).headers.length, 13);
      Directory('validation').createSync(recursive: true);
      File('validation/max_adj_excel_fixture.json').writeAsStringSync(
        jsonEncode({
          'headers': report.headers,
          'types': report.types,
          'widths': report.widths,
          'rows': values,
        }),
      );
    },
  );
}
