import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'max_adjustment_import.dart';

/// The branch and request type come from the authorized action, never the file.
Future<List<Map<String, dynamic>>> parseTibahMaxFile(
  Uint8List bytes, {
  required String fileName,
}) async {
  if (bytes.length > 15 * 1024 * 1024) {
    throw const FormatException('Choose a file smaller than 15 MB.');
  }
  final sheets = fileName.toLowerCase().endsWith('.xlsx')
      ? _xlsxSheets(bytes)
      : [await parseMaxAdjustmentCsv(bytes)];
  for (final rows in sheets) {
    if (rows.isEmpty) continue;
    final headers = rows.first
        .map(
          (v) => v.toString().trim().toLowerCase().replaceAll(
            RegExp(r'[\s-]+'),
            '_',
          ),
        )
        .toList();
    final codeIndex = headers.indexOf('item_code');
    final nameIndex = headers.indexOf('item_name');
    final qtyIndex = headers.indexOf('qty');
    if (codeIndex < 0 || nameIndex < 0 || qtyIndex < 0) continue;
    if (headers.where((v) => v == 'item_code').length != 1 ||
        headers.where((v) => v == 'item_name').length != 1 ||
        headers.where((v) => v == 'qty').length != 1) {
      throw const FormatException(
        'Use one Item Code, Item Name and Qty column.',
      );
    }
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((v) => v.toString().trim().isEmpty)) continue;
      String value(int column) =>
          column < row.length ? row[column].toString().trim() : '';
      final code = value(codeIndex);
      final name = value(nameIndex);
      final qty = num.tryParse(value(qtyIndex));
      if (code.isEmpty ||
          code.startsWith('=') ||
          name.isEmpty ||
          name.startsWith('=') ||
          qty == null ||
          !qty.isFinite ||
          qty < 0 ||
          qty > 1000000000) {
        throw FormatException(
          'Row ${i + 1}: enter Item Code, Item Name and a valid Qty of 0 or more.',
        );
      }
      if (!seen.add(code)) {
        throw FormatException(
          'Row ${i + 1}: duplicate Item Code $code. Keep one row per product.',
        );
      }
      result.add({'item_code': code, 'item_name': name, 'qty': qty});
      if (result.length > 100000) {
        throw const FormatException(
          'Choose a file with no more than 100,000 products.',
        );
      }
    }
    if (result.isEmpty) {
      throw const FormatException('The file has no product rows.');
    }
    return result;
  }
  throw const FormatException(
    'Use the columns Item Code, Item Name and Qty on the first row.',
  );
}

List<List<List<dynamic>>> _xlsxSheets(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.files.fold<int>(0, (sum, f) => sum + f.size) >
        50 * 1024 * 1024) {
      throw const FormatException('The expanded workbook is too large.');
    }
    XmlDocument xml(ArchiveFile f) =>
        XmlDocument.parse(utf8.decode(f.content as List<int>));
    String cellText(XmlElement e) => e.descendants
        .whereType<XmlElement>()
        .where((n) => n.name.local == 't')
        .map((n) => n.innerText)
        .join();
    final stringsFile = archive.findFile('xl/sharedStrings.xml');
    final strings = stringsFile == null
        ? <String>[]
        : xml(stringsFile).descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'si')
              .map(cellText)
              .toList();
    final result = <List<List<dynamic>>>[];
    for (final sheet in archive.files.where(
      (f) =>
          f.isFile && RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name),
    )) {
      final rows = <List<dynamic>>[];
      for (final row in xml(sheet).descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'row',
      )) {
        final cells = <int, String>{};
        for (final cell in row.childElements.where(
          (e) => e.name.local == 'c',
        )) {
          final reference = cell.getAttribute('r') ?? '';
          var column = 0;
          for (final c
              in reference.replaceAll(RegExp('[^A-Z]'), '').codeUnits) {
            column = column * 26 + c - 64;
          }
          if (column < 1 || column > 16384) continue;
          final hasFormula = cell.childElements.any((e) => e.name.local == 'f');
          final raw =
              cell.childElements
                  .where((e) => e.name.local == 'v')
                  .firstOrNull
                  ?.innerText ??
              '';
          final value = switch (cell.getAttribute('t')) {
            's' => strings[int.parse(raw)],
            'inlineStr' => cellText(cell),
            _ => raw,
          };
          // Formula values can be stale; reject them in the selected input fields.
          cells[column - 1] = hasFormula ? '=FORMULA' : value;
        }
        if (cells.isEmpty) continue;
        final last = cells.keys.reduce((a, b) => a > b ? a : b);
        rows.add([for (var c = 0; c <= last; c++) cells[c] ?? '']);
      }
      result.add(rows);
    }
    return result;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'Could not read the XLSX file. Save it in Excel and try again.',
    );
  }
}
