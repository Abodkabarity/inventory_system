import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/store_order_item.dart';
import 'store_branch_identity_registry.dart';

class PrintService {
  static Future<void> printOrders({
    required String branch,
    required List<StoreOrderItem> items,
    required bool isGeneral,
  }) async {
    await StoreBranchIdentityRegistry.load(Supabase.instance.client);

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
        header: (context) => _header(branch),

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

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static pw.Widget _header(String branch) {
    final date = DateTime.now().toLocal();

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 5),

      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _printedBranchHeading(branch),

          pw.Text(
            "${date.day}/${date.month}/${date.year}",
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _printedBranchHeading(String branch) {
    final is71 = StoreBranchIdentityRegistry.isSeventyOne(branch);
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          branch,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        if (is71) ...[
          pw.SizedBox(width: 7),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColors.orange100,
              border: pw.Border.all(color: PdfColors.deepOrange400, width: 0.8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              '71 BRANCH',
              style: pw.TextStyle(
                color: PdfColors.deepOrange800,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
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
