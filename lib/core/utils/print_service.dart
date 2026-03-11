import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../domain/entities/store_order_item.dart';

class PrintService {
  static Future<void> printOrders({
    required String branch,
    required List<StoreOrderItem> items,
    required bool isGeneral,
  }) async {
    final pdf = pw.Document();

    final filtered = items.where((e) {
      final qty = e.quantity;
      final cls = (e.classification ?? '').toLowerCase().trim();

      if (qty <= 0) return false;

      if (isGeneral) {
        return cls == 'general';
      } else {
        return cls != 'general';
      }
    }).toList();

    filtered.sort((a, b) => a.itemName.compareTo(b.itemName));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,

        margin: const pw.EdgeInsets.all(20),

        header: (context) {
          return _header(branch);
        },

        footer: (context) {
          return pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              "Page ${context.pageNumber} / ${context.pagesCount}",
              style: const pw.TextStyle(fontSize: 10),
            ),
          );
        },

        build: (context) {
          return [pw.SizedBox(height: 10), _table(filtered, isGeneral)];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static pw.Widget _header(String branch) {
    final date = DateTime.now();

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),

      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,

        children: [
          pw.Text(
            branch,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),

          pw.Text(
            "${date.day}/${date.month}/${date.year}",
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _table(List<StoreOrderItem> items, bool isGeneral) {
    final headers = isGeneral
        ? ['Qty', 'Item Name', 'Barcode']
        : ['Qty', 'Item Name', 'Supplier'];

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),

      columnWidths: {
        0: const pw.FixedColumnWidth(50),

        1: const pw.FlexColumnWidth(),

        2: const pw.FixedColumnWidth(170),
      },

      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),

          children: headers.map((h) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(6),

              child: pw.Center(
                child: pw.Text(
                  h,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            );
          }).toList(),
        ),

        ...items.map((e) {
          final barcode = e.barcode.toString().replaceAll(".0", "");

          final supplier = e.supplier.length > 18
              ? e.supplier.substring(0, 18)
              : e.supplier;

          return pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Center(child: pw.Text(e.quantity.toString())),
              ),

              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(e.itemName),
              ),

              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(isGeneral ? barcode : supplier),
              ),
            ],
          );
        }),
      ],
    );
  }
}
