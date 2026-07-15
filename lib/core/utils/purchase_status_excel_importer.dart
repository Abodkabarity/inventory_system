import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../domain/entities/purchase_status_record.dart';

class PurchaseStatusExcelImportRow {
  final int recordId;
  final String itemCode;
  final String itemName;
  final String statusName;
  final DateTime statusDate;
  final String alternativeItemCode;
  final String alternativeItemName;
  final String note;

  const PurchaseStatusExcelImportRow({
    required this.recordId,
    required this.itemCode,
    required this.itemName,
    required this.statusName,
    required this.statusDate,
    required this.alternativeItemCode,
    required this.alternativeItemName,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
    'record_id': recordId,
    'item_code': itemCode,
    'item_name': itemName,
    'status_name': statusName,
    'status_date': statusDate.toIso8601String().split('T').first,
    'alternative_item_code': alternativeItemCode,
    'alternative_item_name': alternativeItemName,
    'note': note,
  };
}

class PurchaseStatusExcelImportPreview {
  final List<PurchaseStatusExcelImportRow> rows;
  final int totalRows;
  final int unchangedRows;
  final List<String> newStatuses;

  const PurchaseStatusExcelImportPreview({
    required this.rows,
    required this.totalRows,
    required this.unchangedRows,
    required this.newStatuses,
  });
}

class PurchaseStatusExcelImporter {
  static const _requiredHeaders = {
    'ITEM CODE',
    'ITEM NAME',
    'STATUS',
    'STATUS DATE',
    '_RECORD_ID',
    '_ORIGINAL_STATUS',
    '_ORIGINAL_STATUS_DATE',
    '_ORIGINAL_ALT_CODE',
    '_ORIGINAL_ALT_NAME',
    '_ORIGINAL_NOTE',
  };

  static PurchaseStatusExcelImportPreview parse(
    Uint8List bytes,
    List<PurchaseStatusOption> statuses,
  ) {
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4b ||
        bytes[2] != 0x03 ||
        bytes[3] != 0x04) {
      throw const FormatException(
        'The selected file is not a valid XLSX file.',
      );
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = _readSharedStrings(archive);
    final worksheetFiles = archive.files
        .where(
          (file) =>
              file.isFile &&
              RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name),
        )
        .toList(growable: false);

    for (final file in worksheetFiles) {
      final parsed = _tryParseWorksheet(file, sharedStrings, statuses);
      if (parsed != null) return parsed;
    }
    throw const FormatException(
      'Purchase Status sheet or required import columns were not found. '
      'Please import a file exported from this page.',
    );
  }

  static PurchaseStatusExcelImportPreview? _tryParseWorksheet(
    ArchiveFile file,
    List<String> sharedStrings,
    List<PurchaseStatusOption> statuses,
  ) {
    final document = XmlDocument.parse(_archiveText(file));
    final xmlRows = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'row')
        .toList(growable: false);
    Map<String, int>? headerColumns;
    var headerRowNumber = 0;

    for (final xmlRow in xmlRows) {
      final cells = _readRow(xmlRow, sharedStrings);
      final candidate = <String, int>{};
      for (final entry in cells.entries) {
        final header = _normalizeHeader(entry.value);
        if (header.isNotEmpty) candidate[header] = entry.key;
      }
      if (_requiredHeaders.every(candidate.containsKey)) {
        headerColumns = candidate;
        headerRowNumber = int.tryParse(xmlRow.getAttribute('r') ?? '') ?? 0;
        break;
      }
    }
    if (headerColumns == null) return null;

    final importedRows = <PurchaseStatusExcelImportRow>[];
    final errors = <String>[];
    final seenIds = <int>{};
    var totalRows = 0;
    var unchangedRows = 0;

    for (final xmlRow in xmlRows) {
      final excelRow = int.tryParse(xmlRow.getAttribute('r') ?? '') ?? 0;
      if (excelRow <= headerRowNumber) continue;
      final cells = _readRow(xmlRow, sharedStrings);
      String value(String header) =>
          (cells[headerColumns![header]] ?? '').trim();

      final itemCode = value('ITEM CODE');
      final itemName = value('ITEM NAME');
      final statusName = value('STATUS');
      final idText = value('_RECORD_ID');
      if ([
        itemCode,
        itemName,
        statusName,
        idText,
      ].every((text) => text.isEmpty)) {
        continue;
      }
      totalRows++;

      final recordId = int.tryParse(idText.replaceAll(RegExp(r'\.0$'), ''));
      if (recordId == null) {
        errors.add('Row $excelRow: invalid or missing system record ID.');
        continue;
      }
      if (!seenIds.add(recordId)) {
        errors.add(
          'Row $excelRow: record ID $recordId appears more than once.',
        );
        continue;
      }
      if (itemName.isEmpty) {
        errors.add('Row $excelRow: Item Name is required.');
        continue;
      }

      final dateText = value('STATUS DATE');
      final originalDateText = value('_ORIGINAL_STATUS_DATE');
      final normalizedDate = _normalizedDate(dateText);
      final normalizedOriginalDate = _normalizedDate(originalDateText);
      if (normalizedDate == null || normalizedOriginalDate == null) {
        errors.add('Row $excelRow: invalid Status Date. Use DD/MM/YYYY.');
        continue;
      }

      final alternativeItemCode = value('ALTERNATIVE ITEM CODE');
      final alternativeItemName = value('ALTERNATIVE ITEM NAME');
      final note = value('NOTE');
      final changed =
          _normalizeValue(statusName) !=
              _normalizeValue(value('_ORIGINAL_STATUS')) ||
          normalizedDate != normalizedOriginalDate ||
          alternativeItemCode != value('_ORIGINAL_ALT_CODE') ||
          alternativeItemName != value('_ORIGINAL_ALT_NAME') ||
          note != value('_ORIGINAL_NOTE');
      if (!changed) {
        unchangedRows++;
        continue;
      }
      if (statusName.isEmpty) {
        errors.add('Row $excelRow: Status is required for a modified row.');
        continue;
      }

      final statusDate = dateText.isEmpty
          ? DateTime.now()
          : _parseExcelDate(dateText);
      if (statusDate == null) {
        errors.add(
          'Row $excelRow: invalid Status Date "$dateText". Use DD/MM/YYYY.',
        );
        continue;
      }

      importedRows.add(
        PurchaseStatusExcelImportRow(
          recordId: recordId,
          itemCode: itemCode,
          itemName: itemName,
          statusName: statusName,
          statusDate: statusDate,
          alternativeItemCode: alternativeItemCode,
          alternativeItemName: alternativeItemName,
          note: note,
        ),
      );
    }

    if (errors.isNotEmpty) {
      final visible = errors.take(8).join('\n');
      final remaining = errors.length - 8;
      throw FormatException(
        remaining > 0 ? '$visible\n...and $remaining more errors.' : visible,
      );
    }
    final existingStatuses = statuses
        .map((status) => _normalizeValue(status.name))
        .toSet();
    final newStatusesByKey = <String, String>{};
    for (final row in importedRows) {
      final key = _normalizeValue(row.statusName);
      if (!existingStatuses.contains(key)) {
        newStatusesByKey.putIfAbsent(key, () => row.statusName.trim());
      }
    }
    return PurchaseStatusExcelImportPreview(
      rows: importedRows,
      totalRows: totalRows,
      unchangedRows: unchangedRows,
      newStatuses: newStatusesByKey.values.toList(growable: false),
    );
  }

  static Map<int, String> _readRow(XmlElement row, List<String> sharedStrings) {
    final values = <int, String>{};
    for (final cell in row.childElements.where(
      (element) => element.name.local == 'c',
    )) {
      final reference = cell.getAttribute('r') ?? '';
      final column = _columnIndex(reference);
      if (column == null) continue;
      final type = cell.getAttribute('t');
      String value;
      if (type == 'inlineStr') {
        value = cell.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 't')
            .map((element) => element.innerText)
            .join();
      } else {
        final valueNode = cell.childElements
            .where((element) => element.name.local == 'v')
            .firstOrNull;
        final rawValue = valueNode?.innerText ?? '';
        if (type == 's') {
          final index = int.tryParse(rawValue);
          value = index != null && index >= 0 && index < sharedStrings.length
              ? sharedStrings[index]
              : '';
        } else {
          value = rawValue;
        }
      }
      values[column] = value;
    }
    return values;
  }

  static List<String> _readSharedStrings(Archive archive) {
    final file = archive.files
        .where((entry) => entry.name == 'xl/sharedStrings.xml')
        .firstOrNull;
    if (file == null) return const [];
    final document = XmlDocument.parse(_archiveText(file));
    return document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'si')
        .map(
          (element) => element.descendants
              .whereType<XmlElement>()
              .where((child) => child.name.local == 't')
              .map((child) => child.innerText)
              .join(),
        )
        .toList(growable: false);
  }

  static String _archiveText(ArchiveFile file) {
    return utf8.decode(file.content);
  }

  static int? _columnIndex(String reference) {
    final letters = RegExp(r'^[A-Za-z]+').firstMatch(reference)?.group(0);
    if (letters == null) return null;
    var result = 0;
    for (final unit in letters.toUpperCase().codeUnits) {
      result = result * 26 + unit - 64;
    }
    return result;
  }

  static String _normalizeHeader(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

  static String _normalizeValue(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static String? _normalizedDate(String value) {
    if (value.trim().isEmpty) return '';
    final parsed = _parseExcelDate(value);
    if (parsed == null) return null;
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseExcelDate(String value) {
    final numeric = double.tryParse(value);
    if (numeric != null && numeric > 0) {
      return DateTime(1899, 12, 30).add(
        Duration(milliseconds: (numeric * Duration.millisecondsPerDay).round()),
      );
    }
    final isoDate = DateTime.tryParse(value);
    if (isoDate != null) return isoDate;
    final match = RegExp(
      r'^(\d{1,2})[\-/](\d{1,2})[\-/](\d{4})$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day
        ? parsed
        : null;
  }
}
