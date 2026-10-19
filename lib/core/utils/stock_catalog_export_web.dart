// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

Future<void> saveCsv(String content, String fileName) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([utf8.encode(content)], 'text/csv;charset=utf-8'),
  );
  final link = html.AnchorElement(href: url)..download = fileName;
  html.document.body?.append(link);
  link.click();
  link.remove();
  html.Url.revokeObjectUrl(url);
}
