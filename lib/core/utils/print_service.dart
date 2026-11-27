import 'dart:typed_data';

import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/store_order_item.dart';
import '../../../domain/entities/tibah_order.dart';
import 'store_branch_identity_registry.dart';

class PrintService {
  static Future<void> printOrders({
    required String branch,
    required List<StoreOrderItem> items,
    required bool isGeneral,
    TibahOrder? tibahOrder,
  }) async {
    await StoreBranchIdentityRegistry.load(
      Supabase.instance.client,
      force: tibahOrder != null,
    );

    final bytes = await buildOrdersPdf(
      branch: branch,
      items: items,
      isGeneral: isGeneral,
      tibahOrder: tibahOrder,
    );
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  static Future<Uint8List> buildOrdersPdf({
    required String branch,
    required List<StoreOrderItem> items,
    required bool isGeneral,
    TibahOrder? tibahOrder,
  }) async {
    final pdf = pw.Document();

    final filtered = items.where((e) {
      final qty = e.quantity;
      final cls = e.classification.toLowerCase().trim();

      if (qty <= 0) return false;

      if (isGeneral) {
        return cls.contains('general');
      } else {
        return !cls.contains('general');
      }
    }).toList();

    filtered.sort((a, b) {
      int compareText(String x, String y) {
        return x.trim().toLowerCase().compareTo(y.trim().toLowerCase());
      }

      if (isGeneral) {
        // General:
        // 1. Category (A to Z)
        // 2. Supplier (A to Z)
        // 3. Item Name (A to Z)

        final byCategory = compareText(a.category, b.category);
        if (byCategory != 0) return byCategory;

        final bySupplier = compareText(a.supplier, b.supplier);
        if (bySupplier != 0) return bySupplier;

        return compareText(a.itemName, b.itemName);
      } else {
        // Medicine:
        // 1. Store Classification (A to Z)
        // 2. Supplier (A to Z)
        // 3. Item Name (A to Z)

        final byClassification = compareText(
          a.classification,
          b.classification,
        );
        if (byClassification != 0) return byClassification;

        final bySupplier = compareText(a.supplier, b.supplier);
        if (bySupplier != 0) return bySupplier;

        return compareText(a.itemName, b.itemName);
      }
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,

        margin: const pw.EdgeInsets.fromLTRB(15, 10, 10, 60),

        /// HEADER
        header: (context) => _header(branch, isGeneral, tibahOrder),

        /// FOOTER
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 5),

            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(
                  width: double.infinity,
                  height: 1,
                  color: PdfColors.grey600,
                ),

                pw.SizedBox(height: 6),

                pw.Text(
                  "Page ${context.pageNumber} of ${context.pagesCount}",
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          );
        },

        build: (context) {
          return [pw.SizedBox(height: 0), _table(filtered, isGeneral)];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _header(String branch, bool isGeneral, TibahOrder? order) {
    final date = DateTime.now().toLocal();

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 5),

      child: pw.Column(
        children: [
          if (order != null)
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 7),
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: order.type == TibahOrderType.upp
                    ? PdfColor.fromHex('#6D28D9')
                    : PdfColor.fromHex('#1E40AF'),
                border: pw.Border.all(color: PdfColors.black, width: 1),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    order.type.printLabel(isGeneral).toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.Text(
                    'Order ${order.id.substring(0, 8)} | ${_uploadDate(order.uploadedAt)}',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _printedBranchHeading(branch),

              pw.Text(
                "${date.day}/${date.month}/${date.year}",
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _uploadDate(DateTime? value) {
    if (value == null) return '';
    final date = value.toUtc().add(const Duration(hours: 4));
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} UAE';
  }

  static pw.Widget _printedBranchHeading(String branch) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          StoreBranchIdentityRegistry.displayName(branch),
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static pw.Widget _table(List<StoreOrderItem> items, bool isGeneral) {
    final headers = isGeneral
        ? ['Qty', 'Item Name', 'Barcode']
        : ['Qty', 'Item Name', 'Supplier'];

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5.w),

      columnWidths: {
        0: const pw.FixedColumnWidth(50),
        1: const pw.FlexColumnWidth(),
        2: const pw.FixedColumnWidth(105),
      },

      children: [
        /// HEADER
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),

          children: headers.map((h) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(6),

              child: pw.Center(child: pw.Text(h)),
            );
          }).toList(),
        ),

        /// ROWS
        ...items.map((e) {
          final barcode = e.barcode.toString().replaceAll(".0", "");

          final supplier = e.supplier.length > 18
              ? e.supplier.substring(0, 18)
              : e.supplier;

          return pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Center(
                  child: pw.Text(
                    e.quantity.toString(),
                    style: pw.TextStyle(fontSize: 10),
                  ),
                ),
              ),

              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(e.itemName, style: pw.TextStyle(fontSize: 10)),
              ),

              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  isGeneral ? barcode : supplier,
                  maxLines: 1,
                  style: pw.TextStyle(fontSize: 10),
                  overflow: pw.TextOverflow.clip,
                  softWrap: false,
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}
