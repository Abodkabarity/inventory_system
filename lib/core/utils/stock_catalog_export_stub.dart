import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

Future<void> saveCsv(String content, String fileName) async {
  final bytes = utf8.encode(content);
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save stock report',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['csv'],
    bytes: bytes,
  );
  if (path != null &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await File(path).writeAsBytes(bytes);
  }
}
