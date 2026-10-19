import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

Future<bool> copyTrackerEmailTable(String htmlBody, String plainBody) async {
  await Clipboard.setData(ClipboardData(text: plainBody));
  return false;
}

Future<bool> saveTrackerEmail(String message, String fileName) async {
  final bytes = utf8.encode(message);
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save Outlook draft',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['eml'],
    bytes: bytes,
  );
  if (path == null) return false;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await File(path).writeAsBytes(bytes);
  }
  return true;
}
