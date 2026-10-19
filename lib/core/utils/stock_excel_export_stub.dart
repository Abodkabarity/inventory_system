import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'stock_excel_report.dart';

Future<void> saveExcel(StockExcelReport report, String fileName) async {
  final bytes = Uint8List.fromList(report.buildNative());
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save Excel stock report',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    bytes: bytes,
  );
  if (path != null &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await File(path).writeAsBytes(bytes);
  }
}
