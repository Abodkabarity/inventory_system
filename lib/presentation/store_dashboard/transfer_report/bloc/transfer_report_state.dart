import 'package:equatable/equatable.dart';

import '../../../../data/models/transfer_report_row.dart';

class TransferReportState extends Equatable {
  final bool loading;

  final List<TransferReportRow> rows;

  final String filter;

  const TransferReportState({
    required this.loading,
    required this.rows,
    required this.filter,
  });

  factory TransferReportState.initial() {
    return const TransferReportState(loading: false, rows: [], filter: 'ALL');
  }

  TransferReportState copyWith({
    bool? loading,
    List<TransferReportRow>? rows,
    String? filter,
  }) {
    return TransferReportState(
      loading: loading ?? this.loading,
      rows: rows ?? this.rows,
      filter: filter ?? this.filter,
    );
  }

  int get complete =>
      rows.where((e) => e.status == TransferStatus.complete).length;

  int get partial =>
      rows.where((e) => e.status == TransferStatus.partial).length;

  int get missing =>
      rows.where((e) => e.status == TransferStatus.missing).length;
  int get notInDailyOrder =>
      rows.where((e) => e.status == TransferStatus.notInDailyOrder).length;

  int get extra => rows.where((e) => e.status == TransferStatus.extra).length;

  List<TransferReportRow> get filteredRows {
    if (filter == 'ALL') {
      return rows;
    }

    return rows.where((e) {
      switch (filter) {
        case 'COMPLETE':
          return e.status == TransferStatus.complete;

        case 'PARTIAL':
          return e.status == TransferStatus.partial;

        case 'MISSING':
          return e.status == TransferStatus.missing;

        case 'EXTRA':
          return e.status == TransferStatus.extra;

        case 'NOT_IN_DAILY_ORDER':
          return e.status == TransferStatus.notInDailyOrder;

        default:
          return true;
      }
    }).toList();
  }

  @override
  List<Object?> get props => [loading, rows, filter];
}
