import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrintAdditionalService {
  static Future<void> printBatch(
    Map<String, List<Map<String, dynamic>>> batch,
  ) async {
    final pdf = pw.Document();

    for (final entry in batch.entries) {
      final branch = entry.key;
      final items = entry.value;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),

          /// HEADER
          header: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                branch,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(DateTime.now().toString().substring(0, 10)),
            ],
          ),

          /// CONTENT
          build: (context) => [
            pw.SizedBox(height: 10),

            pw.Table(
              border: pw.TableBorder.all(width: 0.5),

              columnWidths: {
                0: const pw.FixedColumnWidth(40),
                1: const pw.FlexColumnWidth(),
                2: const pw.FixedColumnWidth(80),
              },

              children: [
                /// HEADER
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _cell("Qty", bold: true),
                    _cell("Item Name", bold: true),
                    _cell("Code", bold: true),
                  ],
                ),

                /// ROWS
                ...items.map((e) {
                  return pw.TableRow(
                    children: [
                      _cell((e['request_qty'] ?? '').toString()),
                      _cell(e['item_name'] ?? ''),
                      _cell(e['item_code'] ?? ''),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
