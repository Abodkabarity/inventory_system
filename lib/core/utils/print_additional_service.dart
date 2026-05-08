import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrintAdditionalService {
  static Future<void> printBatch(
    Map<String, List<Map<String, dynamic>>> batch,
  ) async {
    final pdf = pw.Document();

    final sortedEntries = batch.entries.toList()
      ..sort((a, b) {
        final aUrgent = a.value.any((e) => e['contact_logistic'] == 'urgent');

        final bUrgent = b.value.any((e) => e['contact_logistic'] == 'urgent');

        if (aUrgent && !bUrgent) return -1;
        if (!aUrgent && bUrgent) return 1;

        return 0;
      });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),

        build: (context) {
          return [
            ...sortedEntries.expand((entry) {
              final branch = entry.key;
              final items = entry.value;

              final isUrgent = items.any(
                (e) => e['contact_logistic'] == 'urgent',
              );

              return [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          branch,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: isUrgent ? PdfColors.red : PdfColors.black,
                          ),
                        ),

                        if (isUrgent)
                          pw.Text(
                            "URGENT",
                            style: pw.TextStyle(
                              color: PdfColors.red,
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),

                    pw.Text(DateTime.now().toString().substring(0, 10)),
                  ],
                ),

                pw.SizedBox(height: 8),

                pw.TableHelper.fromTextArray(
                  border: pw.TableBorder.all(width: 0.5),

                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),

                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey300,
                  ),

                  cellAlignment: pw.Alignment.center,

                  columnWidths: {
                    0: const pw.FixedColumnWidth(90),
                    1: const pw.FlexColumnWidth(),
                    2: const pw.FixedColumnWidth(40),
                  },

                  headers: ["Item Code", "Item Name", "Qty"],

                  data: items.map((e) {
                    return [
                      (e['item_code'] ?? '').toString(),
                      (e['item_name'] ?? '').toString(),
                      (e['request_qty'] ?? '').toString(),
                    ];
                  }).toList(),

                  rowDecoration: pw.BoxDecoration(color: PdfColors.white),
                ),

                pw.SizedBox(height: 25),
              ];
            }),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
