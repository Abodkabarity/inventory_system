import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:daily_order/core/utils/stock_excel_report.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  test(
    'typed Excel preserves identities, dates, blanks and actual percentages',
    () {
      StoreBranchIdentityRegistry.groups.value = {
        'ZAKHER BRANCH': '71',
        'CITY': 'APG',
      };
      final rows = <Map<String, dynamic>>[
        {
          'Item code': '00123',
          'Product': 'Sample product',
          'branch': 'Zakher Branch',
          'Created date': '01/01/2025',
          'Qty': 12.5,
          'STORE / Total Stock %': 25,
          'Stock / Sales %': 496.153846,
          'Note': '=1+1',
          'Optional': null,
        },
        {
          'Item code': '00345',
          'Product': 'Another product',
          'branch': 'CITY',
          'Created date': '',
          'Qty': 0,
          'STORE / Total Stock %': 0,
          'Stock / Sales %': null,
          'Note': '',
          'Optional': null,
        },
      ];
      final report = StockExcelReport(rows, 'near_expiry.xlsx');
      expect(report.sheetName, 'Near Expiry');
      expect(report.types, [
        'text',
        'text',
        'text',
        'date',
        'number',
        'percent',
        'percent',
        'text',
        'text',
      ]);
      final values = report.values.toList();
      expect(values.first[2], '71 Zakher Branch');
      expect(values.last[2], 'CITY');
      expect(values.first[3], '2025-01-01T00:00:00.000Z');
      expect(values.first[5], 25);
      expect(values.last[6], '');
      expect(rows.first['branch'], 'Zakher Branch');
      final bytes = report.buildNative();
      final archive = ZipDecoder().decodeBytes(bytes);
      String entry(String name) => utf8.decode(
        archive.files.singleWhere((f) => f.name == name).content as List<int>,
      );
      final styles = entry('xl/styles.xml');
      final sheet = entry('xl/worksheets/sheet1.xml');
      expect(styles.toUpperCase(), contains('FF4EB0DE'));
      expect(styles.toUpperCase(), contains('FFFFFFFF'));
      expect(styles, contains('style="thin"'));
      expect(styles, contains('dd/mm/yyyy'));
      expect(styles, contains('0.0%'));
      expect(sheet, contains('autoFilter'));
      expect(sheet, contains('state="frozen"'));
      expect(sheet, contains('<v>0.25</v>'));
      expect(sheet, isNot(contains('<f>')));
      Directory('validation').createSync(recursive: true);
      File('validation/stock_excel_native.xlsx').writeAsBytesSync(bytes);
      File('validation/stock_excel_fixture.json').writeAsStringSync(
        jsonEncode({
          'headers': report.headers,
          'types': report.types,
          'widths': report.widths,
          'rows': values,
          'sheetName': report.sheetName,
        }),
      );
    },
  );
  test(
    'Excel reports validate limits, include later columns and normalize extensions',
    () {
      expect(() => StockExcelReport([], 'report.xlsx'), throwsStateError);
      final report = StockExcelReport([
        {'Code': 'A'},
        {'Code': 'B', 'Extra': 3},
      ], 'stock_overview.xlsx');
      expect(report.headers, ['Code', 'Extra']);
      expect(report.values.first, ['A', '']);
      expect(
        StockExcelReport.fileName('stock_overview.xlsx'),
        'stock_overview.xlsx',
      );
      expect(
        StockExcelReport.fileName('mrn_overview.csv'),
        'mrn_overview.xlsx',
      );
    },
  );
}
