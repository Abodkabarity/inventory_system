import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:daily_order/core/utils/purchase_status_excel_importer.dart';
import 'package:daily_order/core/utils/purchase_status_excel_workbook.dart';
import 'package:daily_order/domain/entities/purchase_status_record.dart';

void main() {
  test('import detects only rows edited after export', () async {
    final record = PurchaseStatusRecord(
      id: 77,
      itemCode: '16-01-00077',
      itemName: 'TEST ITEM',
      statusId: null,
      statusName: 'CUSTOM EXCEL STATUS',
      statusDate: DateTime(2026, 4, 22),
      alternativeItemCode: '',
      alternativeItemName: '',
      note: 'Excel update',
      purchaseStatus: 'NORMAL PURCHASE',
      category: 'MEDICINE',
      supplier: 'TEST SUPPLIER',
      workflowStatus: 'pending',
      reviewOrigin: 'repeated',
    );
    const statuses = [
      PurchaseStatusOption(id: 1, name: 'AVAILABLE'),
      PurchaseStatusOption(id: 2, name: 'NOT AVAILABLE'),
    ];

    final bytes = await PurchaseStatusExcelWorkbook.build([record], statuses);
    final archive = ZipDecoder().decodeBytes(bytes);
    String entry(String name) => utf8.decode(
      archive.files.firstWhere((file) => file.name == name).content,
    );

    expect(entry('xl/workbook.xml'), contains('state="hidden"'));
    final sheetXml = entry('xl/worksheets/sheet1.xml');
    expect(sheetXml, contains('<dataValidations'));
    expect(sheetXml, contains('StatusOptions!\$A\$1:\$A\$2'));
    expect(sheetXml, isNot(contains('showErrorMessage="1"')));
    expect(sheetXml, contains('hidden="1"'));

    final preview = PurchaseStatusExcelImporter.parse(
      Uint8List.fromList(bytes),
      statuses,
    );
    expect(preview.rows, isEmpty);
    expect(preview.totalRows, 1);
    expect(preview.unchangedRows, 1);

    final editedBytes = _replaceCellText(bytes, 'D5', 'UPDATED EXCEL STATUS');
    final editedPreview = PurchaseStatusExcelImporter.parse(
      editedBytes,
      statuses,
    );
    expect(editedPreview.rows, hasLength(1));
    expect(editedPreview.totalRows, 1);
    expect(editedPreview.unchangedRows, 0);
    expect(editedPreview.rows.single.recordId, 77);
    expect(editedPreview.rows.single.statusName, 'UPDATED EXCEL STATUS');
    expect(editedPreview.rows.single.statusDate, DateTime(2026, 4, 22));
    expect(editedPreview.newStatuses, ['UPDATED EXCEL STATUS']);
  });
}

Uint8List _replaceCellText(List<int> workbookBytes, String cell, String text) {
  final source = ZipDecoder().decodeBytes(workbookBytes);
  final sharedStringsFile = source.files.firstWhere(
    (file) => file.name == 'xl/sharedStrings.xml',
  );
  final sharedStrings = XmlDocument.parse(
    utf8.decode(sharedStringsFile.content),
  );
  final stringTable = sharedStrings.rootElement;
  final newIndex = stringTable.childElements
      .where((element) => element.name.local == 'si')
      .length;
  stringTable.children.add(
    XmlElement(XmlName.parts('si'), const [], [
      XmlElement(XmlName.parts('t'), const [], [XmlText(text)]),
    ]),
  );
  stringTable.setAttribute('count', '${newIndex + 1}');
  stringTable.setAttribute('uniqueCount', '${newIndex + 1}');

  final sheetFile = source.files.firstWhere(
    (file) => file.name == 'xl/worksheets/sheet1.xml',
  );
  final sheet = XmlDocument.parse(utf8.decode(sheetFile.content));
  final targetCell = sheet.descendants.whereType<XmlElement>().firstWhere(
    (element) => element.name.local == 'c' && element.getAttribute('r') == cell,
  );
  targetCell.setAttribute('t', 's');
  final value = targetCell.childElements.firstWhere(
    (element) => element.name.local == 'v',
  );
  value.innerText = '$newIndex';

  final updatedArchive = Archive();
  for (final file in source.files) {
    final content = switch (file.name) {
      'xl/sharedStrings.xml' => utf8.encode(sharedStrings.toXmlString()),
      'xl/worksheets/sheet1.xml' => utf8.encode(sheet.toXmlString()),
      _ => file.content,
    };
    updatedArchive.addFile(ArchiveFile(file.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(updatedArchive));
}
