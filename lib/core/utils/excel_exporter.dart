import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class ExcelExporter {
  static Future<void> exportOrdersWeb({
    required List<Map<String, dynamic>> rows,
    required List<String> columns,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];

    // =========================
    // HEADER NAMES
    // =========================

    final headerMap = <String, String>{
      'branch_name': 'Branch',
      'item_code': 'Item Code',
      'item_name': 'Item Name',
      'goods_received_last_7_days': 'GOODS RECEIVED OF LAST 7 DAYS',
      'branch_stock': 'Branch Stock',
      'mismatch_stock': 'MISMATCH STOCK',
      'store_stock': 'STORE STOCK',
      'pending_stock': 'PENDING STOCK RECEIVED',
      'extra_qty': 'Extra QTY (More Than Month)',
      'max_adj': 'MAX ADJUSTMENT (30 DAYS DEMAND BY BRANCH)',
      'max_adj_reason': 'REASON FOR MAX ADJUSTMENT (30 DAYS DEMAND BY BRANCH)',
      'demand_for_30_days': 'DEMAND FOR 30 DAYS',
      'reorder_min': 'REORDER POINT (MIN)',
      'reorder_max': 'REORDER MAX',
      'reorder_qty': 'REORDER QTY',
      'final_reorder_qty_store_stock_gt_0':
          'Final Re Order QTY (Store Stock >0)',
      'qty_30_days_from_last_45d': 'Sales 45 Days',
      'branch_formulary': 'Branch Formulary',
      'additional_request': 'Additional Request',
    };

    // =========================
    // HEADER COLORS
    // =========================

    final headerColors = <String, String>{
      'branch_name': '#D9EAD3',
      'item_code': '#D9EAD3',
      'item_name': '#D9EAD3',
      'goods_received_last_7_days': '#D9E1F2',
      'branch_stock': '#D9E1F2',
      'mismatch_stock': '#D9E1F2',
      'store_stock': '#FCE5CD',
      'pending_stock': '#FCE5CD',
      'extra_qty': '#FCE5CD',
      'max_adj': '#FFF2CC',
      'max_adj_reason': '#FFF2CC',
      'demand_for_30_days': '#EAD1DC',
      'reorder_min': '#EAD1DC',
      'reorder_max': '#EAD1DC',
      'reorder_qty': '#EAD1DC',
      'final_reorder_qty_store_stock_gt_0': '#D9EAD3',
    };

    // =========================
    // HEADER
    // =========================

    for (int c = 0; c < columns.length; c++) {
      final key = columns[c];
      final title = headerMap[key] ?? key;

      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(title);

      cell.cellStyle.bold = true;
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.backColor = headerColors[key] ?? '#E6E8F0';

      // ✅ FIX WIDTH (الصح)
      sheet.getRangeByIndex(1, c + 1).columnWidth = _getColumnWidth(key);
    }

    // =========================
    // DATA
    // =========================

    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];

      for (int c = 0; c < columns.length; c++) {
        final key = columns[c];
        final value = row[key];

        final cell = sheet.getRangeByIndex(r + 2, c + 1);

        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value?.toString() ?? '');
        }

        cell.cellStyle.hAlign = xlsio.HAlignType.center;
        cell.cellStyle.vAlign = xlsio.VAlignType.center;
      }
    }

    // =========================
    // FREEZE HEADER
    // =========================

    // =========================
    // SAVE
    // =========================

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute("download", "orders_export.xlsx")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  // =========================
  // COLUMN WIDTH LOGIC
  // =========================

  static double _getColumnWidth(String key) {
    if (key.contains('name')) return 35;
    if (key.contains('code')) return 22;
    if (key.contains('reason')) return 45;
    if (key.contains('comment')) return 40;
    if (key.contains('date')) return 25;
    if (key.contains('qty')) return 18;
    if (key.contains('stock')) return 18;
    return 22;
  }
}
