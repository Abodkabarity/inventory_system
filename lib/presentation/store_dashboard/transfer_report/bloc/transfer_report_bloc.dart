import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../data/models/transfer_report_row.dart';
import '../../../../domain/repositories/store_repository.dart';
import 'transfer_report_event.dart';
import 'transfer_report_state.dart';

class TransferReportBloc
    extends Bloc<TransferReportEvent, TransferReportState> {
  final StoreRepository repo;

  TransferReportBloc(this.repo) : super(TransferReportState.initial()) {
    on<ImportTransferFile>(_onImport);
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

          if (branch.isEmpty) continue;

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
                (double.tryParse(existing['required_qty'].toString()) ?? 0) +
                qty;
            final classification =
                (existing['store_item_classifications'] ?? '').toString();
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
            if (!entry.key.startsWith('$runDate|$branch|')) {
              continue;
            }

            final code = entry.key.split('|')[2];

            if (orderCodes.contains(code)) {
              continue;
            }

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

      emit(state.copyWith(loading: false, rows: resultRows));
    } catch (e, s) {
      print(e);
      print(s);

      emit(state.copyWith(loading: false));
    }
  }

  void _onFilter(ChangeStatusFilter event, Emitter<TransferReportState> emit) {
    emit(state.copyWith(filter: event.status));
  }

  String _key(String runDate, String branch, String itemCode) {
    return '$runDate|$branch|$itemCode';
  }

  String _parseTransferDate(dynamic value, {required String fallback}) {
    if (value == null) return fallback;

    if (value is DateTime) {
      return DateFormat('yyyy-MM-dd').format(value);
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return fallback;

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
