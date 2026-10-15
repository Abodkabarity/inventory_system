import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:csv/csv_settings_autodetection.dart';

import 'max_adjustment_expiry.dart';
import 'store_branch_identity_registry.dart';

const maxAdjustmentImportHeaders = [
  'action',
  'branch_name',
  'item_code',
  'item_name',
  'current_demand_30d',
  'max_adjustment_30d',
  'reason',
  'update_date',
  'end_date',
];

/// Incremental decoding/parsing bounds each browser task, including quoted
/// fields spanning chunks. Preserve identifiers rather than coercing to numbers.
Future<List<List<dynamic>>> parseMaxAdjustmentCsv(
  Uint8List bytes, {
  void Function(double progress)? onProgress,
  int chunkSize = 16384,
}) async {
  if (chunkSize <= 0) throw ArgumentError.value(chunkSize);
  var lastProgress = 0.0;
  Future<List<List<dynamic>>> decode(Encoding encoding) async {
    Stream<List<int>> chunks() async* {
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, bytes.length);
        yield Uint8List.sublistView(bytes, offset, end);
        lastProgress = (end / bytes.length).clamp(lastProgress, 1.0);
        onProgress?.call(lastProgress);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    final result = <List<dynamic>>[];
    final converter = CsvToListConverter(
      shouldParseNumbers: false,
      allowInvalid: false,
      csvSettingsDetector: const FirstOccurrenceSettingsDetector(
        fieldDelimiters: [','],
        eols: ['\r\n', '\n', '\r'],
      ),
    );
    var first = true;
    final text = encoding.decoder.bind(chunks()).map((chunk) {
      if (!first) return chunk;
      first = false;
      return chunk.startsWith('\uFEFF') ? chunk.substring(1) : chunk;
    });
    await for (final row in converter.bind(text)) {
      result.add(List<dynamic>.from(row));
    }
    return result;
  }

  try {
    return await decode(utf8);
  } on FormatException catch (error) {
    // Only encoding failures fall back. Malformed CSV must remain an error.
    if (!error.message.toLowerCase().contains('utf') &&
        !error.message.toLowerCase().contains('byte') &&
        !error.message.toLowerCase().contains('sequence')) {
      rethrow;
    }
    return decode(latin1);
  }
}

class MaxAdjustmentImportPlan {
  final upserts = <Map<String, dynamic>>[];
  final deletes = <Map<String, dynamic>>[];
  final conflicts = <Map<String, dynamic>>[];
  final issues = <Map<String, dynamic>>[];
  int get writeCount => upserts.length + deletes.length;
}

Future<MaxAdjustmentImportPlan> prepareMaxAdjustmentImport({
  required List<List<dynamic>> rows,
  required List<String> activeBranches,
  required List<Map<String, dynamic>> existing,
  required bool overwrite,
  void Function(int processed, int total)? onProgress,
}) async {
  if (rows.isEmpty) throw const FormatException('CSV is empty.');
  final header = rows.first.map((e) => e.toString().trim()).toList();
  if (header.length < maxAdjustmentImportHeaders.length ||
      !List.generate(
        maxAdjustmentImportHeaders.length,
        (i) => header[i] == maxAdjustmentImportHeaders[i],
      ).every((v) => v)) {
    throw const FormatException(
      'Please use the Max Adjustment import template.',
    );
  }
  final branches = <String, String>{};
  for (final branch in activeBranches) {
    branches[branch.trim().toUpperCase()] = branch;
    branches[StoreBranchIdentityRegistry.displayName(branch).toUpperCase()] =
        branch;
  }
  String key(String branch, String code) => jsonEncode([branch, code]);
  final existingByKey = <String, Map<String, dynamic>>{
    for (final e in existing)
      key(e['branch_name'].toString(), e['item_code'].toString()): e,
  };
  final seen = <String, int>{};
  final plan = MaxAdjustmentImportPlan();
  for (var i = 1; i < rows.length; i++) {
    // Yield before any branch that can continue, including deletes/conflicts.
    if (i % 100 == 0) {
      onProgress?.call(i, rows.length - 1);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final row = rows[i];
    if (row.every((v) => v == null || v.toString().trim().isEmpty)) continue;
    String text(int column) =>
        column < row.length ? (row[column] ?? '').toString().trim() : '';
    try {
      if (row.length < 9) throw const FormatException('Expected 9 columns.');
      final action = text(0).toUpperCase();
      if (!['ADD', 'UPDATE', 'DELETE'].contains(action)) {
        throw FormatException('Invalid action: $action');
      }
      final branch = branches[text(1).toUpperCase()];
      if (branch == null) {
        throw const FormatException('Branch not found or inactive.');
      }
      final code = text(2);
      if (code.isEmpty) throw const FormatException('Item Code is required.');
      final rowKey = key(branch, code);
      if (seen.containsKey(rowKey)) {
        throw FormatException(
          'Repeated branch/item in this file. First appears at row ${seen[rowKey]}.',
        );
      }
      seen[rowKey] = i + 1;
      if (action == 'DELETE') {
        plan.deletes.add({'branch_name': branch, 'item_code': code});
        continue;
      }
      num number(int column) {
        final n = num.tryParse(text(column));
        if (n == null || !n.isFinite || n < 0) {
          throw FormatException(
            'Invalid ${maxAdjustmentImportHeaders[column]}.',
          );
        }
        return n;
      }

      if (text(3).isEmpty) {
        throw const FormatException('Item Name is required.');
      }
      final demand = number(4);
      final max = number(5);
      final data = <String, dynamic>{
        'branch_name': branch,
        'item_code': code,
        'item_name': text(3),
        'current_demand_30d': demand,
        'max_adjustment_30d': max,
        'adjustment_type': max <= demand ? 'DECREASE' : 'INCREASE',
        'reason': text(6),
        'update_date': _date(text(7), required: true),
        'end_date': _date(text(8)),
        'qty': max,
        'added_by': 'inventory',
      };
      final old = existingByKey[rowKey];
      if (old != null && !overwrite) {
        plan.conflicts.add({
          'branch_name': branch,
          'item_code': code,
          'item_name': data['item_name'],
          for (final field in [
            'current_demand',
            'max_adj',
            'reason',
            'adjustment_type',
            'update_date',
            'added_by',
            'end_date',
          ]) ...{
            'old_$field': old[_comparisonField(field)],
            'new_$field': data[_comparisonField(field)],
          },
        });
      } else {
        plan.upserts.add(data);
      }
    } on FormatException catch (error) {
      plan.issues.add({
        'row': i + 1,
        'branch_name': text(1),
        'item_code': text(2),
        'error': error.message,
      });
    }
  }
  onProgress?.call(rows.length - 1, rows.length - 1);
  return plan;
}

String _comparisonField(String field) => switch (field) {
  'current_demand' => 'current_demand_30d',
  'max_adj' => 'max_adjustment_30d',
  _ => field,
};

String? _date(String value, {bool required = false}) {
  if (value.isEmpty) {
    if (required) throw const FormatException('Update Date is required.');
    return null;
  }
  final serial = num.tryParse(value);
  DateTime? parsed;
  if (serial != null && serial.isFinite && serial >= 1 && serial <= 2958465) {
    parsed = DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
  } else {
    parsed = MaxAdjustmentExpiry.parseDate(value);
    if (parsed == null && !RegExp(r'^\d{4}-').hasMatch(value)) {
      parsed = MaxAdjustmentExpiry.parseDate(
        value.replaceAll(RegExp(r'[-.\\]'), '/'),
      );
    }
  }
  if (parsed == null) throw FormatException('Invalid date: $value');
  return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
}

class MaxAdjustmentImportWriteFailure implements Exception {
  MaxAdjustmentImportWriteFailure(this.confirmedRows, this.cause);
  final int confirmedRows;
  final Object cause;
  @override
  String toString() =>
      'Import stopped after $confirmedRows confirmed records. '
      'The last batch may have been saved. Review the refreshed table before retrying. $cause';
}

/// Sequential bounded requests avoid oversized JSON encoding and write races.
/// Never retry a timed-out write automatically: its commit may be uncertain.
Future<int> writeMaxAdjustmentImport({
  required MaxAdjustmentImportPlan plan,
  required Future<void> Function(List<Map<String, dynamic>>) upsert,
  required Future<void> Function(List<Map<String, dynamic>>) delete,
  void Function(int completed, int total)? onProgress,
  int batchSize = 250,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (batchSize <= 0) throw ArgumentError.value(batchSize);
  if (plan.issues.isNotEmpty) {
    throw StateError('Fix validation errors before importing.');
  }
  var completed = 0;
  for (final action in [(plan.deletes, delete), (plan.upserts, upsert)]) {
    for (var i = 0; i < action.$1.length; i += batchSize) {
      final batch = action.$1.sublist(
        i,
        (i + batchSize).clamp(0, action.$1.length),
      );
      try {
        await action.$2(batch).timeout(timeout);
      } catch (error) {
        throw MaxAdjustmentImportWriteFailure(completed, error);
      }
      completed += batch.length;
      onProgress?.call(completed, plan.writeCount);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }
  return completed;
}

Future<String> maxAdjustmentImportReportCsv(
  List<Map<String, dynamic>> rows,
) async {
  if (rows.isEmpty) return '';
  final keys = rows.first.keys.toList();
  final out = StringBuffer('\uFEFF');
  out.writeln(const ListToCsvConverter().convert([keys]));
  for (var i = 0; i < rows.length; i++) {
    out.writeln(
      const ListToCsvConverter().convert([
        [
          for (final key in keys)
            StoreBranchIdentityRegistry.exportValue(key, rows[i][key]) ?? '',
        ],
      ]),
    );
    if (i % 200 == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }
  return out.toString();
}
