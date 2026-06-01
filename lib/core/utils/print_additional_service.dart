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
        final aUrgent = a.value.any(
          (e) =>
              (e['contact_logistic'] ?? '').toString().toLowerCase() ==
              'urgent',
        );

        final bUrgent = b.value.any(
          (e) =>
              (e['contact_logistic'] ?? '').toString().toLowerCase() ==
              'urgent',
        );

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

              final items = [...entry.value]
                ..sort((a, b) {
                  final aUrgent =
                      (a['contact_logistic'] ?? '').toString().toLowerCase() ==
                      'urgent';

                  final bUrgent =
                      (b['contact_logistic'] ?? '').toString().toLowerCase() ==
                      'urgent';

                  if (aUrgent && !bUrgent) return -1;
                  if (!aUrgent && bUrgent) return 1;

                  return 0;
                });

              return [
                pw.Row(
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

                pw.SizedBox(height: 8),

                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(90),
                    1: const pw.FlexColumnWidth(),
                    2: const pw.FixedColumnWidth(40),
                    3: const pw.FixedColumnWidth(70),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                      ),
                      children: [
                        _cell("Item Code", bold: true),
                        _cell("Item Name", bold: true),
                        _cell("Qty", bold: true),
                        _cell("Status", bold: true),
                      ],
                    ),

                    ...items.map((e) {
                      final isUrgent =
                          (e['contact_logistic'] ?? '')
                              .toString()
                              .toLowerCase() ==
                          'urgent';

                      return pw.TableRow(
                        children: [
                          _cell((e['item_code'] ?? '').toString()),

                          _cell((e['item_name'] ?? '').toString()),

                          _cell((e['request_qty'] ?? '').toString()),

                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              isUrgent ? 'URGENT' : '',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                color: isUrgent
                                    ? PdfColors.red
                                    : PdfColors.black,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
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
