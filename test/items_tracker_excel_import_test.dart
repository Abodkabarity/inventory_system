import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:daily_order/core/utils/items_tracker_excel_importer.dart';
import 'package:daily_order/core/utils/items_tracker_excel_workbook.dart';
import 'package:daily_order/domain/entities/items_tracker_record.dart';

void main() {
  Future<Uint8List> workbook() => ItemsTrackerExcelWorkbook.build([
    _record('11111111-1111-4111-8111-111111111111', 'A', 'purchase'),
    _record('22222222-2222-4222-8222-222222222222', 'B', 'purchase'),
    _record('33333333-3333-4333-8333-333333333333', 'C', 'inventory'),
  ], role: 'purchase');

  test(
    'action sheet has only assigned pending rows and report keeps all rows',
    () async {
      final bytes = await workbook();
      final parsed = ItemsTrackerExcelImporter.parse(bytes);
      expect(parsed.rows, isEmpty);
      expect(parsed.blankRows, 2);
      expect(parsed.issues, isEmpty);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(
        utf8.decode(archive.findFile('xl/workbook.xml')!.content),
        contains('Action updates'),
      );
      expect(
        utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content),
        contains('hidden="1"'),
      );
      expect(archive.findFile('xl/worksheets/sheet2.xml'), isNotNull);
      final strings = utf8.decode(
        archive.findFile('xl/sharedStrings.xml')!.content,
      );
      expect(strings, contains('11111111-1111-4111-8111-111111111111'));
      expect(strings, contains('22222222-2222-4222-8222-222222222222'));
      expect(strings, contains('33333333-3333-4333-8333-333333333333'));
      final report = XmlDocument.parse(
        utf8.decode(archive.findFile('xl/worksheets/sheet2.xml')!.content),
      );
      expect(
        report.descendants.whereType<XmlElement>().where(
          (e) => e.name.local == 'row' && int.parse(e.getAttribute('r')!) > 4,
        ),
        hasLength(3),
      );
    },
  );

  test(
    'each department sees its records first while only its pending actions are editable',
    () async {
      final ids = {
        'inventory': '11111111-1111-4111-8111-111111111111',
        'purchase': '22222222-2222-4222-8222-222222222222',
        'category': '33333333-3333-4333-8333-333333333333',
      };
      final records = [
        for (final entry in ids.entries)
          _record(entry.value, entry.key, entry.key),
        _record(
          '44444444-4444-4444-8444-444444444444',
          'DONE',
          'inventory',
          status: 'done',
        ),
      ];
      for (final role in ids.keys) {
        final bytes = await ItemsTrackerExcelWorkbook.build(
          records,
          role: role,
        );
        final archive = ZipDecoder().decodeBytes(bytes);
        final strings = utf8.decode(
          archive.findFile('xl/sharedStrings.xml')!.content,
        );
        for (final id in ids.values) {
          expect(strings, contains(id));
        }
        expect(_cellText(archive, 1, 'A6'), role);
        expect(_cellText(archive, 2, 'C5'), role);
        expect(_dataRowCount(archive, 1, 5), 1);
        expect(_dataRowCount(archive, 2, 4), 4);
        expect(
          _sheetXml(archive, 1),
          isNot(contains('44444444-4444-4444-8444-444444444444')),
        );
      }
    },
  );

  test(
    'done items remain visible in report when no actions are pending',
    () async {
      final bytes = await ItemsTrackerExcelWorkbook.build([
        _record(
          '44444444-4444-4444-8444-444444444444',
          'DONE',
          'inventory',
          status: 'done',
        ),
      ], role: 'inventory');
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(_dataRowCount(archive, 1, 5), 0);
      expect(_dataRowCount(archive, 2, 4), 1);
      expect(_cellText(archive, 2, 'C5'), 'DONE');
    },
  );

  test(
    'blank row preserves system action even with stale or missing metadata',
    () async {
      final edited = _edit(await workbook(), {
        'K6': 'invalid-id',
        'L6': '',
        'G6': '',
        'D6': '0',
        'I7': 'Supplier confirmed a return',
        'J7': '2026-10-05',
        'E7': '0',
      });
      final parsed = ItemsTrackerExcelImporter.parse(edited);
      expect(parsed.blankRows, 1);
      expect(parsed.issues, isEmpty);
      final row = parsed.rows.single;
      expect(row.itemCode, 'B');
      expect(row.itemId, '22222222-2222-4222-8222-222222222222');
      expect(row.body, 'Supplier confirmed a return');
      expect(row.actionDate, DateTime(2026, 10, 5));
      expect(row.expectedVersion, 7);
      expect(row.importToken, isNotEmpty);
      expect(row.toJson().containsKey('unit_cost'), isFalse);
      expect(row.toJson().containsKey('required_qty'), isFalse);
      expect(row.toJson().containsKey('inventory_note'), isFalse);
    },
  );

  test('invalid dates and missing identifiers exclude written rows', () async {
    final parsed = ItemsTrackerExcelImporter.parse(
      _edit(await workbook(), {
        'I6': 'Date invalid',
        'J6': '2026-02-30',
        'I7': 'Missing token',
        'M7': '',
      }),
    );
    expect(parsed.rows, isEmpty);
    expect(parsed.issues, hasLength(2));
  });

  test('duplicate record IDs exclude both copies', () async {
    final parsed = ItemsTrackerExcelImporter.parse(
      _edit(await workbook(), {
        'I6': 'First',
        'I7': 'Second',
        'K7': '11111111-1111-4111-8111-111111111111',
      }),
    );
    expect(parsed.rows, isEmpty);
    expect(parsed.issues.single.message, contains('Duplicate'));
  });

  test('dates accept Excel serials and optional blank date', () async {
    final parsed = ItemsTrackerExcelImporter.parse(
      _edit(await workbook(), {
        'I6': 'Serial date',
        'J6': '46000',
        'I7': 'Default date',
        'J7': '',
      }),
    );
    expect(
      parsed.rows.first.actionDate,
      DateTime(1899, 12, 30).add(const Duration(days: 46000)),
    );
    expect(parsed.rows.last.actionDate, isNull);
  });

  test(
    'formula actions are rejected rather than imported as cached text',
    () async {
      final parsed = ItemsTrackerExcelImporter.parse(
        _edit(await workbook(), {'I6': 'Computed action'}, formulas: {'I6'}),
      );
      expect(parsed.rows, isEmpty);
      expect(parsed.issues.single.message, contains('not a formula'));
    },
  );

  test('damaged or unrelated files produce a clear format error', () {
    expect(
      () => ItemsTrackerExcelImporter.parse(
        Uint8List.fromList(utf8.encode('not xlsx')),
      ),
      throwsFormatException,
    );
  });
}

ItemsTrackerRecord _record(
  String id,
  String code,
  String role, {
  String status = 'pending',
}) => ItemsTrackerRecord.fromMap({
  'id': id,
  'item_code': code,
  'item_name': 'Product $code',
  'company': 'Company',
  'category': 'COSMETICS',
  'follow_up_role': role,
  'row_version': 7,
  'required_qty': 8,
  'unit_cost_snapshot': 11,
  'inventory_note': 'Keep this reason',
  'last_action_body': 'An existing system action',
  'case_status': status,
});

String _sheetXml(Archive archive, int sheet) =>
    utf8.decode(archive.findFile('xl/worksheets/sheet$sheet.xml')!.content);

int _dataRowCount(Archive archive, int sheet, int headerRow) =>
    XmlDocument.parse(_sheetXml(archive, sheet)).descendants
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'row' &&
              int.parse(element.getAttribute('r')!) > headerRow,
        )
        .length;

String _cellText(Archive archive, int sheet, String reference) {
  final shared =
      XmlDocument.parse(
            utf8.decode(archive.findFile('xl/sharedStrings.xml')!.content),
          ).descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'si')
          .map((element) => element.innerText)
          .toList();
  final cell = XmlDocument.parse(_sheetXml(archive, sheet)).descendants
      .whereType<XmlElement>()
      .singleWhere(
        (element) =>
            element.name.local == 'c' && element.getAttribute('r') == reference,
      );
  final value = cell.innerText;
  return cell.getAttribute('t') == 's' ? shared[int.parse(value)] : value;
}

Uint8List _edit(
  Uint8List bytes,
  Map<String, String> edits, {
  Set<String> formulas = const {},
}) {
  final source = ZipDecoder().decodeBytes(bytes);
  final output = Archive();
  for (final file in source.files) {
    var content = file.content;
    if (file.name == 'xl/worksheets/sheet1.xml') {
      final doc = XmlDocument.parse(utf8.decode(content));
      for (final edit in edits.entries) {
        var cell = doc.descendants
            .whereType<XmlElement>()
            .where(
              (e) => e.name.local == 'c' && e.getAttribute('r') == edit.key,
            )
            .firstOrNull;
        if (cell == null) {
          final rowNumber = RegExp(r'\d+$').firstMatch(edit.key)!.group(0);
          final row = doc.descendants.whereType<XmlElement>().firstWhere(
            (e) => e.name.local == 'row' && e.getAttribute('r') == rowNumber,
          );
          cell = XmlElement(XmlName.parts('c'), [
            XmlAttribute(XmlName.parts('r'), edit.key),
          ]);
          row.children.add(cell);
        }
        cell.setAttribute('t', 'inlineStr');
        cell.children.clear();
        if (formulas.contains(edit.key)) {
          cell.children.add(
            XmlElement(XmlName.parts('f'), [], [XmlText('"Computed action"')]),
          );
        }
        cell.children.add(
          XmlElement(XmlName.parts('is'), [], [
            XmlElement(XmlName.parts('t'), [], [XmlText(edit.value)]),
          ]),
        );
      }
      content = Uint8List.fromList(utf8.encode(doc.toXmlString()));
    }
    output.addFile(ArchiveFile(file.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(output));
}
