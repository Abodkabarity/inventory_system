import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrintAdditionalService {
  static Future<void> printBatch(
    Map<String, List<Map<String, dynamic>>> batch,
  ) async {
    final pdf = pw.Document();
    var hasPrintableContent = false;

    final items = <Map<String, dynamic>>[];
    for (final entry in batch.entries) {
      for (final item in entry.value.where(_hasQty)) {
        items.add({...item, 'branch_name': item['branch_name'] ?? entry.key});
      }
    }

    final medicine = items.where((item) => !_isGeneral(item)).toList()
      ..sort(_comparePrintedItems);
    final general = items.where(_isGeneral).toList()
      ..sort(_comparePrintedItems);

    if (medicine.isNotEmpty) {
      hasPrintableContent = true;
      _addSection(
        pdf: pdf,
        title: 'Additional MEDICINE',
        items: medicine,
        isGeneral: false,
      );
    }

    if (general.isNotEmpty) {
      hasPrintableContent = true;
      _addSection(
        pdf: pdf,
        title: 'Additional General',
        items: general,
        isGeneral: true,
      );
    }

    if (!hasPrintableContent) {
      pdf.addPage(
        pw.Page(
          build: (_) => pw.Center(
            child: pw.Text(
              'No additional requests to print',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static void _addSection({
    required pw.Document pdf,
    required String title,
    required List<Map<String, dynamic>> items,
    required bool isGeneral,
  }) {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(15, 10, 10, 60),
        header: (_) => _header(title: title),
        footer: (context) => _footer(context),
        build: (_) => [_table(items, isGeneral)],
      ),
    );
  }

  static pw.Widget _header({required String title}) {
    final now = DateTime.now().toLocal();
    final date =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year}';

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Store Additional Orders',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                date,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: title.toLowerCase().contains('general')
                  ? PdfColors.teal100
                  : PdfColors.blue100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
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
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  static pw.Widget _table(List<Map<String, dynamic>> items, bool isGeneral) {
    final headers = isGeneral
        ? ['Branch', 'Qty', 'Item Name', 'Barcode']
        : ['Branch', 'Qty', 'Item Name', 'Supplier'];

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(125),
        1: const pw.FixedColumnWidth(42),
        2: const pw.FlexColumnWidth(),
        3: const pw.FixedColumnWidth(105),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: headers.map((h) => _cell(h, bold: true)).toList(),
        ),
        ...items.map((e) {
          final urgent = _isUrgent(e);
          final itemName = _string(e['item_name']);
          final barcode = _barcode(e['barcode']);
          final supplier = _truncate(_string(e['supplier']), 18);

          return pw.TableRow(
            decoration: urgent
                ? const pw.BoxDecoration(color: PdfColors.red50)
                : null,
            children: [
              _cell(_string(e['branch_name']), align: pw.TextAlign.left),
              _cell(_qty(e), bold: true),
              _cell(
                urgent ? 'URGENT - $itemName' : itemName,
                align: pw.TextAlign.left,
                color: urgent ? PdfColors.red : PdfColors.black,
                bold: urgent,
              ),
              _cell(isGeneral ? barcode : supplier, align: pw.TextAlign.left),
            ],
          );
        }),
      ],
    );
  }

  static int _compareItems(
    Map<String, dynamic> a,
    Map<String, dynamic> b, {
    required bool isGeneral,
  }) {
    final urgent = _compareUrgent(a, b);
    if (urgent != 0) return urgent;

    if (isGeneral) {
      final byCategory = _text(a['category']).compareTo(_text(b['category']));
      if (byCategory != 0) return byCategory;

      final bySupplier = _text(a['supplier']).compareTo(_text(b['supplier']));
      if (bySupplier != 0) return bySupplier;

      return _text(a['item_name']).compareTo(_text(b['item_name']));
    }

    final byClassification = _text(
      a['store_item_classifications'],
    ).compareTo(_text(b['store_item_classifications']));
    if (byClassification != 0) return byClassification;

    final bySupplier = _text(a['supplier']).compareTo(_text(b['supplier']));
    if (bySupplier != 0) return bySupplier;

    return _text(a['item_name']).compareTo(_text(b['item_name']));
  }

  static int _comparePrintedItems(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final byBranch = _text(a['branch_name']).compareTo(_text(b['branch_name']));
    if (byBranch != 0) return byBranch;

    return _compareItems(a, b, isGeneral: _isGeneral(a));
  }

  static int _compareUrgent(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aUrgent = _isUrgent(a);
    final bUrgent = _isUrgent(b);

    if (aUrgent && !bUrgent) return -1;
    if (!aUrgent && bUrgent) return 1;
    return 0;
  }

  static bool _hasQty(Map<String, dynamic> item) {
    final qty =
        num.tryParse(
          (item['inventory_qty'] ?? item['request_qty'] ?? '0').toString(),
        ) ??
        0;
    return qty > 0;
  }

  static bool _isGeneral(Map<String, dynamic> item) {
    return _text(item['store_item_classifications']).contains('general');
  }

  static bool _isUrgent(Map<String, dynamic> item) {
    return _text(item['contact_logistic']) == 'urgent';
  }

  static String _qty(Map<String, dynamic> item) {
    final value = item['inventory_qty'] ?? item['request_qty'] ?? '';
    final parsed = num.tryParse(value.toString());
    if (parsed == null) return value.toString();
    if (parsed % 1 == 0) return parsed.toInt().toString();
    return parsed.toString();
  }

  static String _barcode(dynamic value) {
    if (value == null) return '';
    if (value is int) return value.toString();
    if (value is double) return value.toStringAsFixed(0);

    final s = value.toString().trim();
    if (s.contains('E+') || s.contains('e+')) {
      final parsed = double.tryParse(s);
      if (parsed != null) return parsed.toStringAsFixed(0);
    }

    return s.replaceAll('.0', '');
  }

  static String _string(dynamic value) {
    return (value ?? '').toString().trim();
  }

  static String _text(dynamic value) {
    return _string(value).toLowerCase();
  }

  static String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return value.substring(0, max);
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.center,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: align,
        maxLines: 2,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
