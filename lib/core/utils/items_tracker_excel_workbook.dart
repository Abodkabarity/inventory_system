import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../domain/entities/items_tracker_record.dart';

/// Creates an Item Tracker workbook containing the user's assigned products.
class ItemsTrackerExcelWorkbook {
  static Future<Uint8List> build(
    List<ItemsTrackerRecord> sourceRecords, {
    required String role,
  }) async {
    final records = sourceRecords
        .where((record) => record.canAct(role))
        .toList(growable: false);
    final workbook = xlsio.Workbook(2);
    _writeActionSheet(workbook.worksheets[0], records, role);
    final sheet = workbook.worksheets[1]..name = 'Items Tracker';
    const headerRow = 4;
    final columns = _columns;

    final title = sheet.getRangeByIndex(1, 1, 1, columns.length)..merge();
    title.setText('ITEMS TRACKER REPORT');
    title.cellStyle
      ..backColor = '#073F4B'
      ..fontColor = '#FFFFFF'
      ..bold = true
      ..fontSize = 18
      ..hAlign = xlsio.HAlignType.center
      ..vAlign = xlsio.VAlignType.center;
    title.rowHeight = 34;

    final subtitle = sheet.getRangeByIndex(2, 1, 2, columns.length)..merge();
    subtitle.setText(
      'Exported ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}  •  ${records.length} tracked records',
    );
    subtitle.cellStyle
      ..backColor = '#E7F3F5'
      ..fontColor = '#355967'
      ..italic = true
      ..hAlign = xlsio.HAlignType.center
      ..vAlign = xlsio.VAlignType.center;
    subtitle.rowHeight = 22;

    for (var column = 0; column < columns.length; column++) {
      final definition = columns[column];
      final cell = sheet.getRangeByIndex(headerRow, column + 1);
      cell.setText(definition.label);
      cell.cellStyle
        ..backColor = definition.group.color
        ..fontColor = '#FFFFFF'
        ..bold = true
        ..fontSize = 10
        ..wrapText = true
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all
        ..lineStyle = xlsio.LineStyle.thin
        ..color = definition.group.borderColor;
      sheet.getRangeByIndex(1, column + 1).columnWidth = definition.width;
    }
    sheet.getRangeByIndex(headerRow, 1, headerRow, columns.length).rowHeight =
        32;

    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      final row = headerRow + index + 1;
      final values = _values(record, index + 1);

      for (var column = 0; column < columns.length; column++) {
        final definition = columns[column];
        final cell = sheet.getRangeByIndex(row, column + 1);
        final value = values[column];
        if (value is num) {
          cell.setNumber(value.toDouble());
          if (definition.currency) cell.numberFormat = '#,##0.00';
          if (definition.quantity) cell.numberFormat = '#,##0.##';
        } else {
          cell.setText(value?.toString() ?? '');
        }
        cell.cellStyle
          ..vAlign = xlsio.VAlignType.center
          ..wrapText = true
          ..hAlign = definition.alignLeft
              ? xlsio.HAlignType.left
              : xlsio.HAlignType.center
          ..backColor = index.isOdd ? '#F8FAFC' : '#FFFFFF';
        cell.cellStyle.borders.all
          ..lineStyle = xlsio.LineStyle.thin
          ..color = '#D7E2E7';
      }

      final statusCell = sheet.getRangeByIndex(row, 16);
      final isPending =
          ItemsTrackerRoles.normalize(record.caseStatus) ==
          ItemsTrackerCaseStatuses.pending;
      statusCell.cellStyle
        ..fontColor = isPending ? '#A85E10' : '#20724F'
        ..bold = true
        ..backColor = isPending ? '#FFF2DE' : '#E4F5EA';

      sheet.getRangeByIndex(row, 1, row, columns.length).rowHeight = 28;
      if (index > 0 && index % 250 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (records.isNotEmpty) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        headerRow,
        1,
        headerRow + records.length,
        columns.length,
      );
    }
    sheet.getRangeByName('A5').freezePanes();

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    return Uint8List.fromList(bytes);
  }

  static void _writeActionSheet(
    xlsio.Worksheet sheet,
    List<ItemsTrackerRecord> records,
    String role,
  ) {
    sheet.name = 'Action updates';
    const headers = [
      'Item code',
      'Item name',
      'Company',
      'Quantity',
      'Cost (AED)',
      'Reason',
      'Current action',
      'Follow up by',
      'Action',
      'Action date',
      '_RECORD_ID',
      '_EXPORT_VERSION',
      '_IMPORT_TOKEN',
    ];
    const widths = [
      18.0,
      44.0,
      25.0,
      12.0,
      15.0,
      42.0,
      42.0,
      18.0,
      54.0,
      18.0,
      2.0,
      2.0,
      2.0,
    ];
    final title = sheet.getRangeByIndex(1, 1, 1, 10)..merge();
    title.setText(
      '${ItemsTrackerRoles.label(role).toUpperCase()} · ACTION UPDATES',
    );
    title.rowHeight = 36;
    title.cellStyle
      ..backColor = '#073F4B'
      ..fontColor = '#FFFFFF'
      ..fontSize = 18
      ..bold = true;
    final instructions = sheet.getRangeByIndex(2, 1, 2, 10)..merge();
    instructions.setText(
      'Write in Action only. Blank Action = keep system data. Action date is optional (YYYY-MM-DD). Other columns are reference only.',
    );
    instructions.rowHeight = 30;
    instructions.cellStyle
      ..backColor = '#E9F8EF'
      ..fontColor = '#216644'
      ..wrapText = true
      ..fontSize = 11;
    final context = sheet.getRangeByIndex(3, 1, 3, 10)..merge();
    context.setText(
      'Exported ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())} · ${records.length} products assigned to your department · Conflicting system changes will be skipped.',
    );
    context.rowHeight = 24;
    context.cellStyle
      ..fontColor = '#71849A'
      ..italic = true;
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(5, c + 1);
      cell.setText(headers[c]);
      cell.columnWidth = widths[c];
      cell.cellStyle
        ..backColor = (c == 8 || c == 9) ? '#198A68' : '#275C70'
        ..fontColor = '#FFFFFF'
        ..bold = true
        ..wrapText = true;
    }
    sheet.getRangeByIndex(5, 1, 5, headers.length).rowHeight = 30;
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final values = <Object?>[
        r.itemCode,
        r.itemName,
        r.company,
        r.requiredQty,
        r.unitCost,
        r.inventoryNote,
        r.lastActionBody,
        ItemsTrackerRoles.label(r.followUpRole),
        '',
        date,
        r.id,
        r.rowVersion,
        const Uuid().v4(),
      ];
      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(i + 6, c + 1);
        final value = values[c];
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value?.toString() ?? '');
        }
        cell.cellStyle
          ..backColor = (c == 8 || c == 9)
              ? '#E9F8EF'
              : (i.isOdd ? '#F6F9FC' : '#FFFFFF')
          ..fontColor = (c == 8 || c == 9) ? '#14553E' : '#19354B'
          ..vAlign = xlsio.VAlignType.center
          ..wrapText = true;
        cell.cellStyle.borders.all
          ..lineStyle = xlsio.LineStyle.thin
          ..color = '#DEE7EF';
        if (c == 4) cell.numberFormat = '#,##0.00';
      }
      sheet.getRangeByIndex(i + 6, 1, i + 6, 10).rowHeight = 48;
    }
    for (var c = 11; c <= 13; c++) {
      sheet.columns[c]!.isHidden = true;
    }
    if (records.isNotEmpty) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        5,
        1,
        records.length + 5,
        10,
      );
    }
    sheet.getRangeByName('A6').freezePanes();
  }

  static List<Object?> _values(ItemsTrackerRecord record, int rowNumber) => [
    rowNumber,
    _date(record.escalatedDate),
    record.itemCode,
    record.itemName,
    record.category,
    record.supplier,
    record.company,
    record.sourceItemStatus,
    record.retailSnapshot,
    record.unitCost,
    record.requiredQty,
    record.requiredValue,
    record.inventoryNote,
    record.statusUpdatedTo,
    ItemsTrackerRoles.label(record.followUpRole),
    ItemsTrackerCaseStatuses.label(record.caseStatus),
    record.latestActivityType,
    record.latestActivityBody,
    _dateTime(record.latestActivityDate ?? record.latestActivityCreatedAt),
    ItemsTrackerRoles.label(record.latestActivityByRole),
    record.latestActivityByName,
    record.latestActivityAttachmentName,
    record.lastActionBody,
    _dateTime(record.lastActionDate),
    ItemsTrackerRoles.label(record.lastActionByRole),
    record.lastFollowUpBody,
    _dateTime(record.lastFollowUpDate),
    ItemsTrackerRoles.label(record.lastFollowUpToRole),
    record.latestComment,
    ItemsTrackerRoles.label(record.commentByRole),
    record.commentByName,
    _dateTime(record.latestCommentAt),
    record.commentCount,
    _dateTime(record.createdAt),
    _dateTime(record.updatedAt),
    record.id,
  ];

  static String _date(DateTime value) =>
      DateFormat('dd MMM yyyy').format(value);

  static String _dateTime(DateTime? value) =>
      value == null ? '' : DateFormat('dd MMM yyyy, HH:mm').format(value);

  static const _columns = <_ExportColumn>[
    _ExportColumn('#', 8, _ExportGroup.identity),
    _ExportColumn('Escalated date', 16, _ExportGroup.identity),
    _ExportColumn('Item code', 18, _ExportGroup.identity),
    _ExportColumn('Item name', 42, _ExportGroup.identity, alignLeft: true),
    _ExportColumn('Category', 20, _ExportGroup.identity),
    _ExportColumn('Supplier', 25, _ExportGroup.identity, alignLeft: true),
    _ExportColumn('Company', 22, _ExportGroup.identity, alignLeft: true),
    _ExportColumn('Item status', 24, _ExportGroup.identity),
    _ExportColumn('Retail (AED)', 15, _ExportGroup.financial, currency: true),
    _ExportColumn(
      'Unit cost (AED)',
      17,
      _ExportGroup.financial,
      currency: true,
    ),
    _ExportColumn('Required qty', 15, _ExportGroup.financial, quantity: true),
    _ExportColumn(
      'Required value (AED)',
      21,
      _ExportGroup.financial,
      currency: true,
    ),
    _ExportColumn(
      'Inventory note',
      36,
      _ExportGroup.financial,
      alignLeft: true,
    ),
    _ExportColumn('Status updated to', 25, _ExportGroup.workflow),
    _ExportColumn('Follow-up department', 23, _ExportGroup.workflow),
    _ExportColumn('Case status', 16, _ExportGroup.workflow),
    _ExportColumn('Latest activity type', 21, _ExportGroup.activity),
    _ExportColumn(
      'Latest activity',
      42,
      _ExportGroup.activity,
      alignLeft: true,
    ),
    _ExportColumn('Latest activity date', 21, _ExportGroup.activity),
    _ExportColumn('Latest activity department', 25, _ExportGroup.activity),
    _ExportColumn('Latest activity by', 25, _ExportGroup.activity),
    _ExportColumn(
      'Latest attachment',
      32,
      _ExportGroup.activity,
      alignLeft: true,
    ),
    _ExportColumn('Last action', 42, _ExportGroup.history, alignLeft: true),
    _ExportColumn('Last action date', 19, _ExportGroup.history),
    _ExportColumn('Last action department', 23, _ExportGroup.history),
    _ExportColumn('Last follow-up', 42, _ExportGroup.history, alignLeft: true),
    _ExportColumn('Last follow-up date', 20, _ExportGroup.history),
    _ExportColumn('Last follow-up to', 23, _ExportGroup.history),
    _ExportColumn('Latest comment', 42, _ExportGroup.history, alignLeft: true),
    _ExportColumn('Comment department', 23, _ExportGroup.history),
    _ExportColumn('Comment by', 25, _ExportGroup.history),
    _ExportColumn('Comment date', 19, _ExportGroup.history),
    _ExportColumn('Comment count', 15, _ExportGroup.history),
    _ExportColumn('Created at', 20, _ExportGroup.system),
    _ExportColumn('Updated at', 20, _ExportGroup.system),
    _ExportColumn('Record ID', 38, _ExportGroup.system, alignLeft: true),
  ];
}

class _ExportColumn {
  final String label;
  final double width;
  final _ExportGroup group;
  final bool alignLeft;
  final bool currency;
  final bool quantity;

  const _ExportColumn(
    this.label,
    this.width,
    this.group, {
    this.alignLeft = false,
    this.currency = false,
    this.quantity = false,
  });
}

enum _ExportGroup {
  identity('#275C70', '#164050'),
  financial('#9972C1', '#6E4B90'),
  workflow('#C97A17', '#95570D'),
  activity('#34829A', '#23647A'),
  history('#626F9D', '#454E77'),
  system('#657984', '#465861');

  final String color;
  final String borderColor;

  const _ExportGroup(this.color, this.borderColor);
}
