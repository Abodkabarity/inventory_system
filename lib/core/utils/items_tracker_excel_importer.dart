import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../domain/entities/items_tracker_action_import.dart';

class ItemsTrackerImportIssue {
  final int excelRow;
  final String message;
  const ItemsTrackerImportIssue(this.excelRow, this.message);
}

class ItemsTrackerActionFile {
  final List<ItemsTrackerActionImport> rows;
  final List<ItemsTrackerImportIssue> issues;
  final int blankRows;
  const ItemsTrackerActionFile({
    required this.rows,
    required this.issues,
    required this.blankRows,
  });
}

/// Reads only the explicit Action input column. Report/snapshot columns are
/// context, never updates. Blank actions are skipped before metadata validation.
class ItemsTrackerExcelImporter {
  static const requiredHeaders = {
    'ITEM CODE',
    'ITEM NAME',
    'ACTION',
    'ACTION DATE',
    '_RECORD_ID',
    '_EXPORT_VERSION',
    '_IMPORT_TOKEN',
  };

  static ItemsTrackerActionFile parse(Uint8List bytes) {
    if (bytes.length > 15 * 1024 * 1024) {
      throw const FormatException('Choose an XLSX file smaller than 15 MB.');
    }
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      if (archive.files.fold<int>(0, (sum, file) => sum + file.size) >
          50 * 1024 * 1024) {
        throw const FormatException('The workbook is too large to import.');
      }
      final strings = _sharedStrings(archive);
      final workbook = archive.findFile('xl/workbook.xml');
      final date1904 =
          workbook != null &&
          XmlDocument.parse(
            _text(workbook),
          ).descendants.whereType<XmlElement>().any(
            (e) =>
                e.name.local == 'workbookPr' &&
                ['1', 'true'].contains(e.getAttribute('date1904')),
          );
      for (final file in archive.files.where(
        (f) =>
            f.isFile &&
            RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name),
      )) {
        final parsed = _worksheet(file, strings, date1904);
        if (parsed != null) return parsed;
      }
      throw const FormatException(
        'Action updates sheet not found. Export a fresh Item Tracker workbook and edit the Action column.',
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Could not read this XLSX file. Open it in Excel, save as XLSX, and try again.',
      );
    }
  }

  static ItemsTrackerActionFile? _worksheet(
    ArchiveFile file,
    List<String> strings,
    bool date1904,
  ) {
    final xmlRows = XmlDocument.parse(_text(file)).descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'row')
        .toList(growable: false);
    Map<String, int>? headers;
    var headerRow = 0;
    for (final row in xmlRows.take(20)) {
      final cells = _cells(row, strings);
      final candidate = {
        for (final entry in cells.entries)
          entry.value.text.trim().toUpperCase(): entry.key,
      };
      if (requiredHeaders.every(candidate.containsKey)) {
        headers = candidate;
        headerRow = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
        break;
      }
    }
    if (headers == null) return null;
    final rows = <ItemsTrackerActionImport>[];
    final issues = <ItemsTrackerImportIssue>[];
    final seen = <String>{};
    var blankRows = 0;
    for (final xmlRow in xmlRows) {
      final rowNumber = int.tryParse(xmlRow.getAttribute('r') ?? '') ?? 0;
      if (rowNumber <= headerRow) continue;
      final cells = _cells(xmlRow, strings);
      String value(String header) =>
          (cells[headers![header]]?.text ?? '').trim();
      final body = value('ACTION');
      if (cells[headers['ACTION']]?.formula ?? false) {
        issues.add(
          ItemsTrackerImportIssue(
            rowNumber,
            'Enter Action as text, not a formula.',
          ),
        );
        continue;
      }
      if (body.isEmpty) {
        if (value('_RECORD_ID').isNotEmpty || value('ITEM CODE').isNotEmpty) {
          blankRows++;
        }
        continue;
      }
      final id = value('_RECORD_ID').toLowerCase();
      final token = value('_IMPORT_TOKEN').toLowerCase();
      final version = int.tryParse(
        value('_EXPORT_VERSION').replaceFirst(RegExp(r'\.0$'), ''),
      );
      final code = value('ITEM CODE');
      if (!_uuid.hasMatch(id) ||
          !_uuid.hasMatch(token) ||
          version == null ||
          version < 1 ||
          code.isEmpty) {
        issues.add(
          ItemsTrackerImportIssue(
            rowNumber,
            'Missing or invalid export identifiers. Export a fresh file; keep hidden columns unchanged.',
          ),
        );
        continue;
      }
      if (!seen.add(id)) {
        issues.add(
          ItemsTrackerImportIssue(
            rowNumber,
            'Duplicate product row. Keep one Action row per product.',
          ),
        );
        // Neither copy of an ambiguous duplicate should be applied.
        rows.removeWhere((r) => r.itemId == id);
        continue;
      }
      final dateText = value('ACTION DATE');
      final date = dateText.isEmpty ? null : _date(dateText, date1904);
      if (dateText.isNotEmpty &&
          (date == null || (cells[headers['ACTION DATE']]?.formula ?? false))) {
        issues.add(
          ItemsTrackerImportIssue(
            rowNumber,
            'Invalid Action date. Use YYYY-MM-DD or DD/MM/YYYY.',
          ),
        );
        continue;
      }
      if (body.length > 32767) {
        issues.add(
          ItemsTrackerImportIssue(
            rowNumber,
            'Action is too long. Use at most 32,767 characters.',
          ),
        );
        continue;
      }
      rows.add(
        ItemsTrackerActionImport(
          excelRow: rowNumber,
          itemId: id,
          itemCode: code,
          itemName: value('ITEM NAME'),
          body: body,
          actionDate: date,
          expectedVersion: version,
          importToken: token,
        ),
      );
    }
    if (rows.length > 1000) {
      throw const FormatException(
        'Import at most 1,000 written actions per file.',
      );
    }
    return ItemsTrackerActionFile(
      rows: rows,
      issues: issues,
      blankRows: blankRows,
    );
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static Map<int, _Cell> _cells(XmlElement row, List<String> strings) {
    final result = <int, _Cell>{};
    for (final cell in row.childElements.where((e) => e.name.local == 'c')) {
      final reference = cell.getAttribute('r') ?? '';
      final letters = RegExp(r'^[A-Za-z]+').firstMatch(reference)?.group(0);
      if (letters == null) continue;
      var column = 0;
      for (final letter in letters.toUpperCase().codeUnits) {
        column = column * 26 + letter - 64;
      }
      final type = cell.getAttribute('t');
      var text = '';
      if (type == 'inlineStr') {
        text = cell.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 't')
            .map((e) => e.innerText)
            .join();
      } else {
        text =
            cell.childElements
                .where((e) => e.name.local == 'v')
                .firstOrNull
                ?.innerText ??
            '';
        if (type == 's') {
          final index = int.tryParse(text);
          text = index != null && index >= 0 && index < strings.length
              ? strings[index]
              : '';
        }
      }
      result[column] = _Cell(
        text,
        cell.childElements.any((e) => e.name.local == 'f'),
      );
    }
    return result;
  }

  static List<String> _sharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return [];
    return XmlDocument.parse(_text(file)).descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'si')
        .map(
          (e) => e.descendants
              .whereType<XmlElement>()
              .where((t) => t.name.local == 't')
              .map((t) => t.innerText)
              .join(),
        )
        .toList();
  }

  static String _text(ArchiveFile file) => utf8.decode(file.content);

  static DateTime? _date(String text, bool date1904) {
    final serial = double.tryParse(text);
    if (serial != null && serial.isFinite && serial >= 1 && serial <= 2958465) {
      final parsed = (date1904 ? DateTime(1904, 1, 1) : DateTime(1899, 12, 30))
          .add(Duration(days: serial.floor()));
      return parsed.year <= 9999 ? parsed : null;
    }
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
    final dmy = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(text);
    if (iso == null && dmy == null) return null;
    final year = int.parse(iso?.group(1) ?? dmy!.group(3)!);
    final month = int.parse(iso?.group(2) ?? dmy!.group(2)!);
    final day = int.parse(iso?.group(3) ?? dmy!.group(1)!);
    final date = DateTime(year, month, day);
    return date.year == year &&
            date.month == month &&
            date.day == day &&
            year >= 1900 &&
            year <= 9999
        ? date
        : null;
  }
}

class _Cell {
  final String text;
  final bool formula;
  const _Cell(this.text, this.formula);
}
