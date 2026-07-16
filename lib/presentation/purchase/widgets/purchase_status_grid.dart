import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/purchase_status_record.dart';

class PurchaseStatusGridController {
  List<PurchaseStatusRecord> _visibleRecords = const [];
  final Map<String, double> _columnWidths = {};
  VoidCallback? _clearGridFilters;

  List<PurchaseStatusRecord> get visibleRecords =>
      List<PurchaseStatusRecord>.unmodifiable(_visibleRecords);

  void _update(List<PurchaseStatusRecord> records) {
    _visibleRecords = List<PurchaseStatusRecord>.of(records);
  }

  void _setColumnWidth(String columnName, double width) {
    _columnWidths[columnName] = width;
  }

  void clearFilters() => _clearGridFilters?.call();
}

class PurchaseStatusGrid extends StatefulWidget {
  final PurchaseStatusGridController controller;
  final List<PurchaseStatusRecord> records;
  final ValueChanged<PurchaseStatusRecord> onEdit;
  final ValueChanged<PurchaseStatusRecord> onHistory;
  final ValueChanged<PurchaseStatusRecord> onDelete;

  const PurchaseStatusGrid({
    super.key,
    required this.controller,
    required this.records,
    required this.onEdit,
    required this.onHistory,
    required this.onDelete,
  });

  @override
  State<PurchaseStatusGrid> createState() => _PurchaseStatusGridState();
}

class _PurchaseStatusGridState extends State<PurchaseStatusGrid> {
  static const _initialWidths = <String, double>{
    'report_date': 145,
    'workflow': 145,
    'item_code': 155,
    'item_name': 310,
    'status': 225,
    'status_date': 155,
    'alternative': 300,
    'purchase_status': 225,
    'category': 180,
    'supplier': 235,
    'note': 250,
    'actions': 145,
  };

  late final _PurchaseStatusDataSource _source;
  late final Map<String, double> _columnWidths;

  @override
  void initState() {
    super.initState();
    _columnWidths = Map<String, double>.of(_initialWidths)
      ..addAll(widget.controller._columnWidths);
    _source = _PurchaseStatusDataSource(
      records: widget.records,
      onEdit: widget.onEdit,
      onHistory: widget.onHistory,
      onDelete: widget.onDelete,
    );
    widget.controller._clearGridFilters = _source.clearFilters;
    widget.controller._update(widget.records);
  }

  @override
  void dispose() {
    widget.controller._clearGridFilters = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PurchaseStatusGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _source
      ..onEdit = widget.onEdit
      ..onHistory = widget.onHistory
      ..onDelete = widget.onDelete;
    if (!identical(oldWidget.records, widget.records)) {
      _source.updateRecords(widget.records);
      widget.controller._update(widget.records);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SfDataGridTheme(
      data: SfDataGridThemeData(
        headerColor: const Color(0xffeaf4fb),
        gridLineColor: const Color(0xffcfd9e3),
        selectionColor: AppColors.primaryColor.withValues(alpha: .12),
        sortIconColor: AppColors.primaryColor,
        filterIconColor: AppColors.primaryColor,
        filterIconHoverColor: AppColors.primaryColor,
      ),
      child: SfDataGrid(
        source: _source,
        allowFiltering: true,
        allowSorting: true,
        allowMultiColumnSorting: true,
        allowTriStateSorting: true,
        allowColumnsResizing: true,
        columnResizeMode: ColumnResizeMode.onResize,
        onColumnResizeUpdate: (details) {
          setState(() {
            _columnWidths[details.column.columnName] = details.width;
          });
          widget.controller._setColumnWidth(
            details.column.columnName,
            details.width,
          );
          return true;
        },
        gridLinesVisibility: GridLinesVisibility.both,
        headerGridLinesVisibility: GridLinesVisibility.both,
        columnWidthMode: ColumnWidthMode.none,
        frozenColumnsCount: 4,
        rowHeight: 64,
        headerRowHeight: 66,
        selectionMode: SelectionMode.single,
        navigationMode: GridNavigationMode.cell,
        onFilterChanged: (_) {
          widget.controller._update(_source.visibleRecords);
        },
        onColumnSortChanged: (_, _) {
          widget.controller._update(_source.visibleRecords);
        },
        columns: [
          GridColumn(
            columnName: 'report_date',
            width: _columnWidths['report_date']!,
            minimumWidth: 125,
            label: _PurchaseGridHeader('REPORT DATE'),
          ),
          GridColumn(
            columnName: 'workflow',
            width: _columnWidths['workflow']!,
            minimumWidth: 125,
            allowSorting: false,
            label: _PurchaseGridHeader('REVIEW'),
          ),
          GridColumn(
            columnName: 'item_code',
            width: _columnWidths['item_code']!,
            minimumWidth: 115,
            label: _PurchaseGridHeader('ITEM CODE'),
          ),
          GridColumn(
            columnName: 'item_name',
            width: _columnWidths['item_name']!,
            minimumWidth: 190,
            label: _PurchaseGridHeader('ITEM NAME', alignLeft: true),
          ),
          GridColumn(
            columnName: 'status',
            width: _columnWidths['status']!,
            minimumWidth: 160,
            label: _PurchaseGridHeader('STATUS'),
          ),
          GridColumn(
            columnName: 'status_date',
            width: _columnWidths['status_date']!,
            minimumWidth: 125,
            label: _PurchaseGridHeader('STATUS DATE'),
          ),
          GridColumn(
            columnName: 'alternative',
            width: _columnWidths['alternative']!,
            minimumWidth: 190,
            label: _PurchaseGridHeader('ALTERNATIVE', alignLeft: true),
          ),
          GridColumn(
            columnName: 'purchase_status',
            width: _columnWidths['purchase_status']!,
            minimumWidth: 160,
            label: _PurchaseGridHeader('PURCHASE STATUS', alignLeft: true),
          ),
          GridColumn(
            columnName: 'category',
            width: _columnWidths['category']!,
            minimumWidth: 130,
            label: _PurchaseGridHeader('CATEGORY', alignLeft: true),
          ),
          GridColumn(
            columnName: 'supplier',
            width: _columnWidths['supplier']!,
            minimumWidth: 160,
            label: _PurchaseGridHeader('SUPPLIER', alignLeft: true),
          ),
          GridColumn(
            columnName: 'note',
            width: _columnWidths['note']!,
            minimumWidth: 150,
            label: _PurchaseGridHeader('NOTE', alignLeft: true),
          ),
          GridColumn(
            columnName: 'actions',
            width: _columnWidths['actions']!,
            minimumWidth: 130,
            allowFiltering: false,
            allowSorting: false,
            label: _PurchaseGridHeader('ACTIONS'),
          ),
        ],
      ),
    );
  }
}

class _PurchaseStatusDataSource extends DataGridSource {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  List<PurchaseStatusRecord> _records;
  List<DataGridRow> _rows = const [];
  final Map<DataGridRow, PurchaseStatusRecord> _recordByRow = {};
  final Map<int, PurchaseStatusRecord> _cachedRecordById = {};
  final Map<int, DataGridRow> _cachedRowById = {};

  ValueChanged<PurchaseStatusRecord> onEdit;
  ValueChanged<PurchaseStatusRecord> onHistory;
  ValueChanged<PurchaseStatusRecord> onDelete;

  _PurchaseStatusDataSource({
    required List<PurchaseStatusRecord> records,
    required this.onEdit,
    required this.onHistory,
    required this.onDelete,
  }) : _records = records {
    _rebuildRows();
  }

  void updateRecords(List<PurchaseStatusRecord> records) {
    _records = records;
    _rebuildRows();
    notifyListeners();
  }

  void _rebuildRows() {
    _rows = _records
        .map((record) {
          final cachedRecord = _cachedRecordById[record.id];
          final cachedRow = _cachedRowById[record.id];
          if (identical(cachedRecord, record) && cachedRow != null) {
            return cachedRow;
          }

          final alternative = record.alternativeItemCode.isEmpty
              ? ''
              : '${record.alternativeItemCode} — ${record.alternativeItemName}';
          final row = DataGridRow(
            cells: [
              DataGridCell<DateTime?>(
                columnName: 'report_date',
                value: record.missingLastReportDate,
              ),
              DataGridCell<String>(
                columnName: 'workflow',
                value: record.workflowStatus,
              ),
              DataGridCell<String>(
                columnName: 'item_code',
                value: record.itemCode,
              ),
              DataGridCell<String>(
                columnName: 'item_name',
                value: record.itemName,
              ),
              DataGridCell<String>(
                columnName: 'status',
                value: record.statusName,
              ),
              DataGridCell<String>(
                columnName: 'status_date',
                value: record.statusDate == null
                    ? ''
                    : _dateFormat.format(record.statusDate!),
              ),
              DataGridCell<String>(
                columnName: 'alternative',
                value: alternative,
              ),
              DataGridCell<String>(
                columnName: 'purchase_status',
                value: record.purchaseStatus,
              ),
              DataGridCell<String>(
                columnName: 'category',
                value: record.category,
              ),
              DataGridCell<String>(
                columnName: 'supplier',
                value: record.supplier,
              ),
              DataGridCell<String>(columnName: 'note', value: record.note),
              const DataGridCell<String>(columnName: 'actions', value: ''),
            ],
          );
          if (cachedRow != null) _recordByRow.remove(cachedRow);
          _cachedRecordById[record.id] = record;
          _cachedRowById[record.id] = row;
          _recordByRow[row] = record;
          return row;
        })
        .toList(growable: false);
  }

  @override
  List<DataGridRow> get rows => _rows;

  List<PurchaseStatusRecord> get visibleRecords => effectiveRows
      .map((row) => _recordByRow[row])
      .whereType<PurchaseStatusRecord>()
      .toList(growable: false);

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final record = _recordByRow[row];
    return DataGridRowAdapter(
      cells: row
          .getCells()
          .map((cell) {
            if (cell.columnName == 'report_date') {
              final reportDate = cell.value as DateTime?;
              return Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: SelectableText(
                  reportDate == null ? '—' : _dateFormat.format(reportDate),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.primaryColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            }
            final value = (cell.value ?? '').toString();
            if (cell.columnName == 'workflow') {
              return Center(
                child: _WorkflowChip(
                  record: record!,
                  onTap: record.isPending ? () => onEdit(record) : null,
                ),
              );
            }
            if (cell.columnName == 'status') {
              if (value.isEmpty) return const SizedBox.shrink();
              return Center(child: _GridStatusChip(value));
            }
            if (cell.columnName == 'actions' && record != null) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GridActionButton(
                    tooltip: record.isPending ? 'Review item' : 'Edit',
                    icon: record.isPending
                        ? Icons.rate_review_outlined
                        : Icons.edit_outlined,
                    color: record.isPending
                        ? const Color(0xffd58a12)
                        : AppColors.primaryColor,
                    onPressed: () => onEdit(record),
                  ),
                  _GridActionButton(
                    tooltip: 'History',
                    icon: Icons.history_rounded,
                    color: AppColors.secondaryColor,
                    onPressed: () => onHistory(record),
                  ),
                  _GridActionButton(
                    tooltip: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    color: const Color(0xffd95050),
                    onPressed: () => onDelete(record),
                  ),
                ],
              );
            }
            final leftAligned = const {
              'item_name',
              'alternative',
              'purchase_status',
              'category',
              'supplier',
              'note',
            }.contains(cell.columnName);
            return Container(
              alignment: leftAligned ? Alignment.centerLeft : Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: SelectableText(
                value.isEmpty ? '—' : value,
                maxLines: 2,
                textAlign: leftAligned ? TextAlign.left : TextAlign.center,
                style: TextStyle(
                  color: cell.columnName == 'item_code'
                      ? AppColors.secondaryColor
                      : AppColors.text,
                  fontSize: 12.5,
                  fontWeight: cell.columnName == 'item_code'
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _PurchaseGridHeader extends StatelessWidget {
  final String title;
  final bool alignLeft;

  const _PurchaseGridHeader(this.title, {this.alignLeft = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: SelectableText(
        title,
        maxLines: 2,
        textAlign: alignLeft ? TextAlign.left : TextAlign.center,
        style: const TextStyle(
          color: AppColors.secondaryColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .25,
        ),
      ),
    );
  }
}

class _WorkflowChip extends StatelessWidget {
  final PurchaseStatusRecord record;
  final VoidCallback? onTap;

  const _WorkflowChip({required this.record, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pending = record.isPending;
    final color = pending ? const Color(0xffd58a12) : const Color(0xff0f9f7f);
    final originLabel = record.wasAlreadyExisting
        ? 'ALREADY EXISTS'
        : 'NEW ITEM';
    final originColor = record.wasAlreadyExisting
        ? const Color(0xffc4322b)
        : const Color(0xff087a5b);
    return Tooltip(
      message: pending ? 'Click to review this item' : 'Review completed',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: .22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      pending
                          ? Icons.pending_actions_rounded
                          : Icons.task_alt_rounded,
                      size: 15,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pending ? 'PENDING' : 'COMPLETE',
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                if (pending) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: originColor.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      originLabel,
                      style: TextStyle(
                        color: originColor,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridStatusChip extends StatelessWidget {
  final String value;
  const _GridStatusChip(this.value);

  @override
  Widget build(BuildContext context) {
    final upper = value.toUpperCase();
    final color = upper.contains('AVAILABLE') && !upper.contains('NOT')
        ? const Color(0xff0f9f7f)
        : upper.contains('OUT OF STOCK') || upper == 'OOS'
        ? const Color(0xffd95050)
        : upper.contains('PENDING')
        ? const Color(0xffd58a12)
        : AppColors.primaryColor;
    return Container(
      constraints: const BoxConstraints(maxWidth: 205),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _GridActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _GridActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 38,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 19, color: color),
      ),
    );
  }
}
