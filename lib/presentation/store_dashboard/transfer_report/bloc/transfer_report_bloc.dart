import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

      final Map<String, double> transfers = {};

      final Map<String, String> names = {};

      final Map<String, String> branches = {};

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

        final itemCode = row[7].toString().trim();

        final itemName = row[8].toString().trim();

        final qty =
            double.tryParse(row[11].toString().replaceAll(',', '')) ?? 0;

        if (branch.isEmpty || itemCode.isEmpty) {
          continue;
        }

        final key = '$branch|$itemCode';

        transfers.update(key, (v) => v + qty, ifAbsent: () => qty);

        names[key] = itemName;

        branches[key] = branch;
      }

      final resultRows = <TransferReportRow>[];

      final branchNames = branches.values.toSet();

      for (final branch in branchNames) {
        final orderRows = await repo.fetchDailyOrderForBranch(
          branch: branch,
          runDate: event.runDate,
        );

        final orderCodes = <String>{};

        final transferredCodes = transfers.keys
            .where((e) => e.startsWith('$branch|'))
            .map((e) => e.split('|')[1])
            .toSet();

        for (final item in orderRows) {
          final code = item['item_code'].toString().trim();

          orderCodes.add(code);

          final requiredQty =
              double.tryParse(
                item['total_final_reorder_today']?.toString() ?? '0',
              ) ??
              0;

          final key = '$branch|$code';

          final transferred = transfers[key] ?? 0;

          TransferStatus status;

          /// =========================
          /// MISSING

          /// =========================
          if (!transferredCodes.contains(code)) {
            status = TransferStatus.missing;
          }
          /// =========================
          /// PARTIAL
          /// =========================
          else if (transferred < requiredQty) {
            status = TransferStatus.partial;
          }
          /// =========================
          /// COMPLETE
          /// =========================
          else if (transferred == requiredQty) {
            status = TransferStatus.complete;
          }
          /// =========================
          /// EXTRA
          /// =========================
          else {
            status = TransferStatus.extra;
          }

          resultRows.add(
            TransferReportRow(
              branch: branch,
              itemCode: code,
              itemName: item['item_name']?.toString() ?? '',
              requiredQty: requiredQty,
              transferredQty: transferred,
              status: status,
            ),
          );
        }

        for (final entry in transfers.entries) {
          if (!entry.key.startsWith('$branch|')) {
            continue;
          }

          final code = entry.key.split('|')[1];

          if (orderCodes.contains(code)) {
            continue;
          }

          resultRows.add(
            TransferReportRow(
              branch: branch,
              itemCode: code,
              itemName: names[entry.key] ?? '',
              requiredQty: 0,
              transferredQty: entry.value,
              status: TransferStatus.notInDailyOrder,
            ),
          );
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
}
