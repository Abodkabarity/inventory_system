// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/services.dart';

@JS('navigator.clipboard')
external _Clipboard get _clipboard;

extension type _Clipboard(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSArray<_ClipboardItem> data);
}

@JS('ClipboardItem')
extension type _ClipboardItem._(JSObject _) implements JSObject {
  external factory _ClipboardItem(JSObject data);
}

@JS('Blob')
extension type _ClipboardBlob._(JSObject _) implements JSObject {
  external factory _ClipboardBlob(JSArray<JSString> parts, JSObject options);
}

_ClipboardBlob _textBlob(String content, String mime) {
  final options = JSObject()..setProperty('type'.toJS, mime.toJS);
  return _ClipboardBlob([content.toJS].toJS, options);
}

Future<bool> copyTrackerEmailTable(String htmlBody, String plainBody) async {
  try {
    final types = JSObject()
      ..setProperty('text/html'.toJS, _textBlob(htmlBody, 'text/html'))
      ..setProperty('text/plain'.toJS, _textBlob(plainBody, 'text/plain'));
    await _clipboard.write([_ClipboardItem(types)].toJS).toDart;
    return true;
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: plainBody));
    return false;
  }
}

Future<bool> saveTrackerEmail(String message, String fileName) async {
  final blob = html.Blob([utf8.encode(message)], 'message/rfc822');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final link = html.AnchorElement(href: url)..download = fileName;
  html.document.body?.append(link);
  try {
    link.click();
    // Allow the browser to consume the object URL before releasing it.
    await Future<void>.delayed(const Duration(seconds: 1));
    return true;
  } finally {
    link.remove();
    html.Url.revokeObjectUrl(url);
  }
}
