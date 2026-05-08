import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' hide Column;

import '../../presentation/orders/widgets/orders_table.dart';

class InventoryOrdersExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required List<String> visibleColumns,
  }) async {
    final workbook = Workbook();

    final sheet = workbook.worksheets[0];

    sheet.name = 'Daily Order';

    /// =========================
    /// HEADER
    /// =========================

    for (int i = 0; i < visibleColumns.length; i++) {
      final key = visibleColumns[i];

      final title = OrdersTable.titles[key] ?? key;

      final cell = sheet.getRangeByIndex(1, i + 1);

      cell.setText(title);

      final group = _groupFor(key);

      cell.cellStyle.bold = true;
      cell.cellStyle.fontSize = 11;
      cell.cellStyle.hAlign = HAlignType.center;
      cell.cellStyle.vAlign = VAlignType.center;
      cell.cellStyle.wrapText = true;

      cell.cellStyle.backColor = group.bg;
      cell.cellStyle.fontColor = group.fg;

      cell.cellStyle.borders.all.lineStyle = LineStyle.thin;
    }

    /// =========================
    /// ROWS
    /// =========================

    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];

      for (int c = 0; c < visibleColumns.length; c++) {
        final key = visibleColumns[c];

        final value = row[key]?.toString() ?? '';

        final cell = sheet.getRangeByIndex(r + 2, c + 1);

        cell.setText(value);

        cell.cellStyle.fontSize = 10;
        cell.cellStyle.vAlign = VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = LineStyle.thin;

        /// ALIGNMENTS
        if (key == 'item_name' ||
            key == 'supplier' ||
            key == 'company' ||
            key == 'active_ingredient' ||
            key == 'indication') {
          cell.cellStyle.hAlign = HAlignType.left;
        } else {
          cell.cellStyle.hAlign = HAlignType.center;
        }

        /// FORMULARY COLORS
        if (key == 'branch_formulary') {
          final upper = value.trim().toUpperCase();

          if (upper == 'ESSENTIAL') {
            cell.cellStyle.fontColor = '#16A34A';
          } else if (upper == 'NON') {
            cell.cellStyle.fontColor = '#DC2626';
          } else if (upper == 'TMA') {
            cell.cellStyle.fontColor = '#2563EB';
          }
        }

        /// STOCK COLORS
        if (key == 'branch_stock') {
          final n = num.tryParse(value) ?? 0;

          if (n <= 0) {
            cell.cellStyle.fontColor = '#DC2626';
          } else if (n < 3) {
            cell.cellStyle.fontColor = '#F59E0B';
          }
        }

        if (key == 'mismatch_stock') {
          final n = num.tryParse(value) ?? 0;

          if (n < 0) {
            cell.cellStyle.fontColor = '#DC2626';
          } else if (n > 0) {
            cell.cellStyle.fontColor = '#F59E0B';
          }
        }
      }
    }

    /// =========================
    /// COLUMN WIDTHS
    /// =========================

    for (int i = 0; i < visibleColumns.length; i++) {
      final key = visibleColumns[i];

      double width = 18;

      if (key == 'item_name') {
        width = 45;
      } else if (key == 'supplier') {
        width = 25;
      } else if (key == 'branch') {
        width = 22;
      } else if (key.contains('reason')) {
        width = 35;
      }

      sheet.getRangeByIndex(1, i + 1, rows.length + 1, i + 1).columnWidth =
          width;
    }

    /// HEADER HEIGHT
    sheet.getRangeByIndex(1, 1, 1, visibleColumns.length).rowHeight = 32;

    /// AUTO FILTER
    sheet.autoFilters.filterRange = sheet.getRangeByIndex(
      1,
      1,
      rows.length + 1,
      visibleColumns.length,
    );

    /// =========================
    /// EXPORT
    /// =========================

    final bytes = workbook.saveAsStream();

    workbook.dispose();

    final blob = html.Blob([Uint8List.fromList(bytes)]);

    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'daily_order_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      )
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  static _ExportGroup _groupFor(String key) {
    if ({'row_no', 'item_code', 'item_name', 'branch'}.contains(key)) {
      return _ExportGroup(bg: '#EFF6FF', fg: '#0B2A4A');
    }

    if ({
      'goods_received_last_7_days',
      'branch_stock',
      'store_stock',
      'mismatch_stock',
      'pending_stock_received',
    }.contains(key)) {
      return _ExportGroup(bg: '#EFFAF3', fg: '#0F3D1F');
    }

    if ({
      'qty_30_days_from_last_45d',
      'demand_for_30_days',
      'total_sold_qty_cash_last_90',
      'total_sold_qty_online_last_90',
      'total_sold_qty_insurance_last_90',
    }.contains(key)) {
      return _ExportGroup(bg: '#FFF7E6', fg: '#5A3A00');
    }

    if ({
      'branch_formulary',
      'assortment_qty_base_stock',
      'assortment_by',
      'max_adjustment_30d',
      'reason_for_max_adjustment_30d',
      'tma_qty',
      'tma_start',
      'tma_end',
    }.contains(key)) {
      return _ExportGroup(bg: '#F3F0FF', fg: '#2B1C5A');
    }

    if ({
      'final_reorder_qty_store_stock_gt_0',
      'reorder_qty',
      'reorder_max',
      'reorder_point_min',
    }.contains(key)) {
      return _ExportGroup(bg: '#FFEEF2', fg: '#5A1025');
    }

    return _ExportGroup(bg: '#F6F7FB', fg: '#374151');
  }
}

class _ExportGroup {
  final String bg;
  final String fg;

  _ExportGroup({required this.bg, required this.fg});
}
