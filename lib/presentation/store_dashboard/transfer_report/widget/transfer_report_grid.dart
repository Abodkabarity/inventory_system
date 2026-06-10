import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../../data/models/transfer_report_row.dart';

class TransferReportGrid extends StatefulWidget {
  final List<TransferReportRow> rows;

  const TransferReportGrid({super.key, required this.rows});

  @override
  State<TransferReportGrid> createState() => _TransferReportGridState();
}

class _TransferReportGridState extends State<TransferReportGrid> {
  final Map<String, double> columnWidths = {
    'status': 170.w,
    'branch': 160.w,
    'itemCode': 160.w,
    'itemName': 250.w,
    'requiredQty': 160.w,
    'transferredQty': 160.w,
    'diff': 140.w,
    'completion': 140.w,
  };

  @override
  Widget build(BuildContext context) {
    final source = TransferReportDataSource(widget.rows);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 12),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SfDataGrid(
          source: source,

          allowColumnsResizing: true,

          columnResizeMode: ColumnResizeMode.onResize,

          onColumnResizeUpdate: (details) {
            setState(() {
              columnWidths[details.column.columnName] = details.width;
            });

            return true;
          },

          allowSorting: true,
          allowFiltering: true,
          allowMultiColumnSorting: true,

          gridLinesVisibility: GridLinesVisibility.both,

          headerGridLinesVisibility: GridLinesVisibility.both,

          columnWidthMode: ColumnWidthMode.none,

          columns: [
            GridColumn(
              width: columnWidths['status']!,
              columnName: 'status',
              label: _header('Status'),
            ),

            GridColumn(
              width: columnWidths['branch']!,
              columnName: 'branch',
              label: _header('Branch'),
            ),

            GridColumn(
              width: columnWidths['itemCode']!,
              columnName: 'itemCode',
              label: _header('Item Code'),
            ),

            GridColumn(
              width: columnWidths['itemName']!,
              columnName: 'itemName',
              label: _header('Item Name'),
            ),

            GridColumn(
              width: columnWidths['requiredQty']!,
              columnName: 'requiredQty',
              label: _header('َQuantity in Order'),
            ),

            GridColumn(
              width: columnWidths['transferredQty']!,
              columnName: 'transferredQty',
              label: _header('Prepared by Store'),
            ),

            GridColumn(
              width: columnWidths['diff']!,
              columnName: 'diff',
              label: _header('Difference'),
            ),

            GridColumn(
              width: columnWidths['completion']!,
              columnName: 'completion',
              label: _header('Completion %'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String title) {
    return Container(
      alignment: Alignment.center,
      color: const Color(0xff243B53),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class TransferReportDataSource extends DataGridSource {
  TransferReportDataSource(List<TransferReportRow> data) {
    _rows = data.map((e) {
      String statusText;

      switch (e.status) {
        case TransferStatus.complete:
          statusText = 'COMPLETE';
          break;

        case TransferStatus.partial:
          statusText = 'PARTIAL';
          break;

        case TransferStatus.missing:
          statusText = 'MISSING';
          break;

        case TransferStatus.extra:
          statusText = 'EXTRA';
          break;

        case TransferStatus.notInDailyOrder:
          statusText = 'NOT IN DAILY ORDER';
          break;
      }

      return DataGridRow(
        cells: [
          DataGridCell<String>(columnName: 'status', value: statusText),

          DataGridCell<String>(columnName: 'branch', value: e.branch),

          DataGridCell<String>(columnName: 'itemCode', value: e.itemCode),

          DataGridCell<String>(columnName: 'itemName', value: e.itemName),

          DataGridCell<double>(columnName: 'requiredQty', value: e.requiredQty),

          DataGridCell<double>(
            columnName: 'transferredQty',
            value: e.transferredQty,
          ),

          DataGridCell<double>(columnName: 'diff', value: e.diff),

          DataGridCell<double>(columnName: 'completion', value: e.completion),
        ],
      );
    }).toList();
  }

  late List<DataGridRow> _rows;

  @override
  List<DataGridRow> get rows => _rows;

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETE':
        return const Color(0xffE8F8F0);

      case 'PARTIAL':
        return const Color(0xffFFF8E1);

      case 'MISSING':
        return const Color(0xffFDEDEC);

      case 'EXTRA':
        return const Color(0xffEBF5FB);
      case 'NOT IN DAILY ORDER':
        return const Color(0xffFDEDEC);

      default:
        return Colors.white;
    }
  }

  Color _statusTextColor(String status) {
    switch (status) {
      case 'COMPLETE':
        return const Color(0xff27AE60);

      case 'PARTIAL':
        return const Color(0xffF39C12);

      case 'MISSING':
        return const Color(0xffE74C3C);

      case 'EXTRA':
        return const Color(0xff3498DB);
      case 'NOT IN DAILY ORDER':
        return const Color(0xffC0392B);

      default:
        return Colors.black;
    }
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final status = row.getCells()[0].value.toString();

    return DataGridRowAdapter(
      color: _statusColor(status),
      cells: [
        Container(
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _statusTextColor(status).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _statusTextColor(status).withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _statusTextColor(status),
              ),
            ),
          ),
        ),

        _cell(row.getCells()[1].value),
        _cell(row.getCells()[2].value),
        _cell(row.getCells()[3].value, alignment: Alignment.centerLeft),
        _cell(row.getCells()[4].value),
        _cell(row.getCells()[5].value),
        _cell(row.getCells()[6].value),
        _cell('${(row.getCells()[7].value as double).toStringAsFixed(1)}%'),
      ],
    );
  }

  Widget _cell(dynamic value, {Alignment alignment = Alignment.center}) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffD6DCE5), width: 0.8),
      ),
      child: Text(
        value.toString(),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}
