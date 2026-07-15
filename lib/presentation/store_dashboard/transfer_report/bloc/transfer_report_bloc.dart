import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:xml/xml.dart';

import '../../../../data/models/transfer_report_row.dart';
import '../../../../domain/repositories/store_repository.dart';
import 'transfer_report_event.dart';
import 'transfer_report_state.dart';

class TransferReportBloc
    extends Bloc<TransferReportEvent, TransferReportState> {
  final StoreRepository repo;

  TransferReportBloc(this.repo) : super(TransferReportState.initial()) {
    on<ImportTransferFile>(_onImport);
    on<ImportSeventyOneDvnFile>(_onImportSeventyOneDvn);
    on<ChangeStatusFilter>(_onFilter);
  }

  Future<void> _onImport(
    ImportTransferFile event,
    Emitter<TransferReportState> emit,
  ) async {
    emit(state.copyWith(loading: true));

    try {
      String csvText;

      try {
        csvText = utf8.decode(event.bytes);
      } catch (_) {
        csvText = latin1.decode(event.bytes);
      }

      final csvRows = const CsvToListConverter().convert(csvText);

      final transfers = <String, double>{};
      final names = <String, String>{};
      final branchesByDate = <String, Set<String>>{};

      for (int i = 1; i < csvRows.length; i++) {
        final row = csvRows[i];

        if (row.length < 12) {
          continue;
        }
        final status = row[6].toString().trim().toUpperCase();
        final transferType = row[5].toString().trim().toUpperCase();

        if (status != 'APPROVED' || transferType != 'DAILY ORDER') {
          continue;
        }
        final branch = row[1].toString().trim();

        final runDate = _parseTransferDate(row[3], fallback: event.runDate);

        final itemCode = row[7].toString().trim();

        final itemName = row[8].toString().trim();

        final qty =
            double.tryParse(row[11].toString().replaceAll(',', '')) ?? 0;

        if (branch.isEmpty || itemCode.isEmpty) {
          continue;
        }

        final key = _key(runDate, branch, itemCode);

        transfers.update(key, (v) => v + qty, ifAbsent: () => qty);

        names[key] = itemName;

        branchesByDate.putIfAbsent(runDate, () => <String>{}).add(branch);
      }

      final resultRows = await _buildReconciliationRows(
        transfers: transfers,
        names: names,
        branchesByDate: branchesByDate,
      );

      emit(state.copyWith(loading: false, rows: resultRows));
    } catch (e, s) {
      print(e);
      print(s);

      emit(state.copyWith(loading: false));
    }
  }

  Future<void> _onImportSeventyOneDvn(
    ImportSeventyOneDvnFile event,
    Emitter<TransferReportState> emit,
  ) async {
    emit(state.copyWith(loading: true));

    try {
      final dvnRows = _readTabularRows(event.bytes, event.fileName);
      if (dvnRows.isEmpty) {
        emit(state.copyWith(loading: false, rows: const []));
        return;
      }

      final header = dvnRows.first.map((e) => e.toString()).toList();
      final branchIndex = _findColumn(header, const [
        'customerref',
        'customerr',
        'customerreference',
      ]);
      final dateIndex = _findColumn(header, const ['dvndate', 'dvnda', 'date']);
      final itemCodeIndex = _findColumn(header, const ['itemcode', 'itemcod']);
      final itemNameIndex = _findColumn(header, const ['itemname']);
      final qtyIndex = _findColumn(header, const ['qty', 'quantity', 'qt']);

      if ([
        branchIndex,
        dateIndex,
        itemCodeIndex,
        itemNameIndex,
        qtyIndex,
      ].any((index) => index < 0)) {
        emit(state.copyWith(loading: false, rows: const []));
        return;
      }

      final seventyOneBranches = await repo.fetchSeventyOneBranchNames();
      final branchesByLookup = {
        for (final branch in seventyOneBranches)
          _normalizeBranch(branch): branch,
      };

      final transfers = <String, double>{};
      final names = <String, String>{};
      final branchesByDate = <String, Set<String>>{};

      for (int i = 1; i < dvnRows.length; i++) {
        final row = dvnRows[i];
        final branchRaw = _cell(row, branchIndex);
        final branch = _matchSeventyOneBranch(branchRaw, branchesByLookup);
        if (branch == null) continue;

        final runDate = _parseTransferDate(
          _cell(row, dateIndex),
          fallback: event.runDate,
        );
        final itemCode = _cell(row, itemCodeIndex);
        final itemName = _cell(row, itemNameIndex);
        final qty = _parseQty(_cell(row, qtyIndex));

        if (itemCode.isEmpty || qty == 0) continue;

        final key = _key(runDate, branch, itemCode);
        transfers.update(key, (value) => value + qty, ifAbsent: () => qty);
        names[key] = itemName;
        branchesByDate.putIfAbsent(runDate, () => <String>{}).add(branch);
      }

      final resultRows = await _buildReconciliationRows(
        transfers: transfers,
        names: names,
        branchesByDate: branchesByDate,
      );

      emit(state.copyWith(loading: false, rows: resultRows, filter: 'ALL'));
    } catch (e, s) {
      print(e);
      print(s);
      emit(state.copyWith(loading: false));
    }
  }

  Future<List<TransferReportRow>> _buildReconciliationRows({
    required Map<String, double> transfers,
    required Map<String, String> names,
    required Map<String, Set<String>> branchesByDate,
  }) async {
    final resultRows = <TransferReportRow>[];

    for (final dateEntry in branchesByDate.entries) {
      final runDate = dateEntry.key;
      final branchNames = dateEntry.value.toList();

      final orderRows = await repo.fetchDailyOrderMovementsForBranches(
        branches: branchNames,
        runDate: runDate,
      );

      final ordersByBranch = <String, Map<String, Map<String, dynamic>>>{};
      for (final row in orderRows) {
        final branch = (row['branch'] ?? '').toString().trim();
        final code = (row['item_code'] ?? '').toString().trim();
        if (branch.isEmpty || code.isEmpty) continue;

        final qty = double.tryParse((row['qty'] ?? '0').toString()) ?? 0;

        final branchRows = ordersByBranch.putIfAbsent(
          branch,
          () => <String, Map<String, dynamic>>{},
        );

        final existing = branchRows[code];
        if (existing == null) {
          branchRows[code] = {
            'branch': branch,
            'item_code': code,
            'item_name': (row['item_name'] ?? '').toString(),
            'store_item_classifications':
                (row['store_item_classifications'] ?? '').toString(),
            'required_qty': qty,
          };
        } else {
          existing['required_qty'] =
              (double.tryParse(existing['required_qty'].toString()) ?? 0) + qty;
          final classification = (existing['store_item_classifications'] ?? '')
              .toString();
          if (classification.trim().isEmpty) {
            existing['store_item_classifications'] =
                (row['store_item_classifications'] ?? '').toString();
          }
        }
      }

      for (final branch in branchNames) {
        final branchOrderRows =
            ordersByBranch[branch]?.values.toList() ?? const [];
        final orderCodes = <String>{};

        final transferredCodes = transfers.keys
            .where((e) => e.startsWith('$runDate|$branch|'))
            .map((e) => e.split('|')[2])
            .toSet();

        for (final item in branchOrderRows) {
          final code = item['item_code'].toString().trim();
          orderCodes.add(code);

          final requiredQty =
              double.tryParse(item['required_qty']?.toString() ?? '0') ?? 0;
          final key = _key(runDate, branch, code);
          final transferred = transfers[key] ?? 0;

          TransferStatus status;
          if (!transferredCodes.contains(code)) {
            status = TransferStatus.missing;
          } else if (transferred < requiredQty) {
            status = TransferStatus.partial;
          } else if (transferred == requiredQty) {
            status = TransferStatus.complete;
          } else {
            status = TransferStatus.extra;
          }

          resultRows.add(
            TransferReportRow(
              branch: branch,
              runDate: runDate,
              itemCode: code,
              itemName: item['item_name']?.toString() ?? '',
              storeItemClassifications:
                  item['store_item_classifications']?.toString() ?? '',
              requiredQty: requiredQty,
              transferredQty: transferred,
              status: status,
            ),
          );
        }

        for (final entry in transfers.entries) {
          if (!entry.key.startsWith('$runDate|$branch|')) continue;

          final code = entry.key.split('|')[2];
          if (orderCodes.contains(code)) continue;

          resultRows.add(
            TransferReportRow(
              branch: branch,
              runDate: runDate,
              itemCode: code,
              itemName: names[entry.key] ?? '',
              storeItemClassifications: '',
              requiredQty: 0,
              transferredQty: entry.value,
              status: TransferStatus.notInDailyOrder,
            ),
          );
        }
      }
    }

    return resultRows;
  }

  void _onFilter(ChangeStatusFilter event, Emitter<TransferReportState> emit) {
    emit(state.copyWith(filter: event.status));
  }

  String _key(String runDate, String branch, String itemCode) {
    return '$runDate|$branch|$itemCode';
  }

  List<List<dynamic>> _readTabularRows(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.xlsx')) return _readXlsxRows(bytes);

    String csvText;
    try {
      csvText = utf8.decode(bytes);
    } catch (_) {
      csvText = latin1.decode(bytes);
    }
    return const CsvToListConverter().convert(csvText);
  }

  List<List<dynamic>> _readXlsxRows(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String readFile(String name) {
      final file = archive.files.firstWhere(
        (entry) => entry.name == name,
        orElse: () => ArchiveFile.string('', ''),
      );
      if (file.name.isEmpty) return '';
      return utf8.decode(file.content as List<int>);
    }

    final sharedStringsXml = readFile('xl/sharedStrings.xml');
    final sharedStrings = <String>[];
    if (sharedStringsXml.isNotEmpty) {
      final document = XmlDocument.parse(sharedStringsXml);
      for (final si in document.findAllElements('si')) {
        sharedStrings.add(
          si.findAllElements('t').map((e) => e.innerText).join(),
        );
      }
    }

    final workbookRels = readFile('xl/_rels/workbook.xml.rels');
    final workbookXml = readFile('xl/workbook.xml');
    var sheetPath = 'xl/worksheets/sheet1.xml';
    if (workbookRels.isNotEmpty && workbookXml.isNotEmpty) {
      final workbook = XmlDocument.parse(workbookXml);
      final firstSheet = workbook.findAllElements('sheet').firstOrNull;
      final relId = firstSheet?.getAttribute('r:id');
      if (relId != null) {
        final rels = XmlDocument.parse(workbookRels);
        final rel = rels
            .findAllElements('Relationship')
            .where((e) => e.getAttribute('Id') == relId)
            .firstOrNull;
        final target = rel?.getAttribute('Target');
        if (target != null && target.isNotEmpty) {
          sheetPath = 'xl/${target.replaceFirst('../', '')}';
        }
      }
    }

    final sheetXml = readFile(sheetPath);
    if (sheetXml.isEmpty) return const [];

    final document = XmlDocument.parse(sheetXml);
    final rows = <List<dynamic>>[];
    for (final rowNode in document.findAllElements('row')) {
      final valuesByColumn = <int, dynamic>{};
      var maxColumn = -1;
      var sequentialColumn = 0;

      for (final cell in rowNode.findElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final column = _columnIndexFromRef(ref) ?? sequentialColumn;
        sequentialColumn = column + 1;
        maxColumn = column > maxColumn ? column : maxColumn;

        final type = cell.getAttribute('t');
        final valueNode = cell.findElements('v').firstOrNull;
        final inlineNode = cell.findElements('is').firstOrNull;
        final rawValue = valueNode?.innerText ?? inlineNode?.innerText ?? '';

        if (type == 's') {
          final index = int.tryParse(rawValue) ?? -1;
          valuesByColumn[column] = index >= 0 && index < sharedStrings.length
              ? sharedStrings[index]
              : '';
        } else {
          valuesByColumn[column] = rawValue;
        }
      }

      rows.add([for (var i = 0; i <= maxColumn; i++) valuesByColumn[i] ?? '']);
    }
    return rows;
  }

  int? _columnIndexFromRef(String ref) {
    final letters = RegExp(r'^[A-Z]+').stringMatch(ref.toUpperCase());
    if (letters == null || letters.isEmpty) return null;
    var result = 0;
    for (final codeUnit in letters.codeUnits) {
      result = result * 26 + (codeUnit - 64);
    }
    return result - 1;
  }

  int _findColumn(List<String> header, List<String> aliases) {
    final normalized = header.map(_normalizeHeader).toList();
    for (var i = 0; i < normalized.length; i++) {
      final value = normalized[i];
      if (aliases.any((alias) => value == alias || value.contains(alias))) {
        return i;
      }
    }
    return -1;
  }

  String _normalizeHeader(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _cell(List<dynamic> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].toString().trim();
  }

  double _parseQty(String value) {
    return double.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }

  String _normalizeBranch(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String? _matchSeventyOneBranch(
    String rawValue,
    Map<String, String> branchesByLookup,
  ) {
    final lookup = _normalizeBranch(rawValue);
    if (lookup.isEmpty) return null;
    final exact = branchesByLookup[lookup];
    if (exact != null) return exact;

    for (final entry in branchesByLookup.entries) {
      if (lookup.contains(entry.key) || entry.key.contains(lookup)) {
        return entry.value;
      }
    }
    return null;
  }

  String _parseTransferDate(dynamic value, {required String fallback}) {
    if (value == null) return fallback;

    if (value is num) {
      final excelEpoch = DateTime.utc(1899, 12, 30);
      return DateFormat(
        'yyyy-MM-dd',
      ).format(excelEpoch.add(Duration(days: value.floor())));
    }

    if (value is DateTime) {
      return DateFormat('yyyy-MM-dd').format(value);
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return fallback;

    final numeric = num.tryParse(raw);
    if (numeric != null && numeric > 20000 && numeric < 80000) {
      final excelEpoch = DateTime.utc(1899, 12, 30);
      return DateFormat(
        'yyyy-MM-dd',
      ).format(excelEpoch.add(Duration(days: numeric.floor())));
    }

    final normalized = raw.replaceAll('/', '-');
    final formats = [
      'yyyy-MM-dd',
      'dd-MM-yyyy',
      'd-M-yyyy',
      'dd-MMM-yy',
      'd-MMM-yy',
      'dd-MMM-yyyy',
      'd-MMM-yyyy',
      'MM-dd-yyyy',
      'M-d-yyyy',
    ];

    for (final pattern in formats) {
      try {
        final parsed = DateFormat(pattern, 'en_US').parseStrict(normalized);
        return DateFormat('yyyy-MM-dd').format(parsed);
      } catch (_) {
        // Try next supported transfer date format.
      }
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return DateFormat('yyyy-MM-dd').format(parsed);
    }

    return fallback;
  }
}
