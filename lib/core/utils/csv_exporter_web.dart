// lib/core/utils/csv_exporter_web.dart
import 'dart:convert';
import 'dart:html' as html;

class CsvExporterWeb {
  static void downloadCsv({
    required List<Map<String, dynamic>> rows,
    required List<String> columns,
    String fileName = 'table_export.csv',
  }) {
    final buffer = StringBuffer();

    // header
    buffer.writeln(columns.map(_csvEscape).join(','));

    // rows
    for (final r in rows) {
      final line = columns
          .map((c) {
            final v = r[c];
            return _csvEscape(v == null ? '' : v.toString());
          })
          .join(',');
      buffer.writeln(line);
    }

    final bytes = utf8.encode(buffer.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final a = html.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none';

    html.document.body?.children.add(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);
  }

  static String _csvEscape(String v) {
    final s = v.replaceAll('\r', ' ').replaceAll('\n', ' ');
    if (s.contains(',') || s.contains('"')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
