import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/items_tracker_record.dart';

class ItemsTrackerGridController {
  VoidCallback? _clearGridFilters;
  List<ItemsTrackerRecord> _visibleRecords = const [];

  List<ItemsTrackerRecord> get visibleRecords => _visibleRecords;

  void clearFilters() => _clearGridFilters?.call();

  void _updateVisible(List<ItemsTrackerRecord> records) {
    _visibleRecords = records;
  }
}

class ItemsTrackerGrid extends StatefulWidget {
  final ItemsTrackerGridController controller;
  final List<ItemsTrackerRecord> records;
  final String role;
  final ValueChanged<ItemsTrackerRecord> onEditInventory;
  final ValueChanged<ItemsTrackerRecord> onAction;
  final ValueChanged<ItemsTrackerRecord> onHistory;
  final ValueChanged<ItemsTrackerRecord> onComment;

  const ItemsTrackerGrid({
    super.key,
    required this.controller,
    required this.records,
    required this.role,
    required this.onEditInventory,
    required this.onAction,
    required this.onHistory,
    required this.onComment,
  });

  @override
  State<ItemsTrackerGrid> createState() => _ItemsTrackerGridState();
}

class _ItemsTrackerGridState extends State<ItemsTrackerGrid> {
  static const _initialWidths = <String, double>{
    'escalated_date': 145,
    'item_code': 150,
    'item_name': 285,
    'category': 155,
    'supplier': 210,
    'company': 190,
    'item_status': 220,
    'unit_cost': 145,
    'inventory_note': 270,
    'required_qty': 145,
    'required_value': 170,
    'follow_up': 155,
    'status_updated_to': 220,
    'last_activity': 330,
    'action_date': 160,
    'case_status': 155,
    'latest_comment': 300,
    'comment_by': 150,
    'actions': 190,
  };

  static const _columnOrderDefault = <String>[
    'escalated_date',
    'item_code',
    'item_name',
    'category',
    'supplier',
    'company',
    'item_status',
    'unit_cost',
    'inventory_note',
    'required_qty',
    'required_value',
    'follow_up',
    'status_updated_to',
    'last_activity',
    'action_date',
    'case_status',
    'latest_comment',
    'comment_by',
    'actions',
  ];

  late final ItemsTrackerDataSource _source;
  late final Map<String, double> _widths;
  late final List<String> _columnOrder;
  late final ScrollController _horizontalController;

  @override
  void initState() {
    super.initState();
    _widths = Map<String, double>.of(_initialWidths);
    _columnOrder = [..._columnOrderDefault];
    _horizontalController = ScrollController();
    _source = ItemsTrackerDataSource(
      records: widget.records,
      role: widget.role,
      onEditInventory: widget.onEditInventory,
      onAction: widget.onAction,
      onHistory: widget.onHistory,
      onComment: widget.onComment,
    );
    widget.controller._clearGridFilters = _source.clearFilters;
    widget.controller._updateVisible(widget.records);
  }

  @override
  void didUpdateWidget(covariant ItemsTrackerGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _source
      ..role = widget.role
      ..onEditInventory = widget.onEditInventory
      ..onAction = widget.onAction
      ..onHistory = widget.onHistory
      ..onComment = widget.onComment;
    if (!identical(oldWidget.records, widget.records)) {
      _source.updateRecords(widget.records);
      widget.controller._updateVisible(widget.records);
    }
  }

  @override
  void dispose() {
    widget.controller._clearGridFilters = null;
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          AppColors.primaryColor.withValues(alpha: .78),
        ),
        trackColor: WidgetStatePropertyAll(
          AppColors.primaryColor.withValues(alpha: .08),
        ),
        thickness: const WidgetStatePropertyAll(11),
        radius: const Radius.circular(12),
        thumbVisibility: const WidgetStatePropertyAll(true),
        trackVisibility: const WidgetStatePropertyAll(true),
      ),
      child: SfDataGridTheme(
        data: SfDataGridThemeData(
          headerColor: Colors.white,
          gridLineColor: const Color(0xffdce3ea),
          selectionColor: AppColors.primaryColor.withValues(alpha: .12),
          filterIconColor: AppColors.secondaryColor,
          sortIconColor: AppColors.primaryColor,
        ),
        child: SfDataGrid(
          key: const ValueKey('itemsTrackerGrid'),
          source: _source,
          horizontalScrollController: _horizontalController,
          isScrollbarAlwaysShown: true,
          showHorizontalScrollbar: true,
          allowFiltering: true,
          allowSorting: true,
          allowMultiColumnSorting: true,
          allowTriStateSorting: true,
          allowColumnsResizing: true,
          columnResizeMode: ColumnResizeMode.onResize,
          allowColumnsDragging: true,
          gridLinesVisibility: GridLinesVisibility.both,
          headerGridLinesVisibility: GridLinesVisibility.both,
          columnWidthMode: ColumnWidthMode.none,
          frozenColumnsCount: 3,
          rowHeight: 76,
          headerRowHeight: 68,
          selectionMode: SelectionMode.single,
          navigationMode: GridNavigationMode.cell,
          onCellDoubleTap: (details) {
            final rowIndex = details.rowColumnIndex.rowIndex;
            if (rowIndex <= 0) return;
            final record = _source.recordAtEffectiveIndex(rowIndex - 1);
            if (record == null) return;
            if (record.canAct(widget.role)) {
              widget.onAction(record);
            } else {
              widget.onHistory(record);
            }
          },
          onFilterChanged: (_) =>
              widget.controller._updateVisible(_source.visibleRecords),
          onColumnSortChanged: (_, _) =>
              widget.controller._updateVisible(_source.visibleRecords),
          onColumnResizeUpdate: (details) {
            setState(() => _widths[details.column.columnName] = details.width);
            return true;
          },
          onColumnDragging: (details) {
            if (details.action != DataGridColumnDragAction.dropping ||
                details.to == null ||
                details.from == details.to) {
              return true;
            }
            setState(() {
              final key = _columnOrder.removeAt(details.from);
              _columnOrder.insert(details.to!, key);
            });
            return true;
          },
          columnDragFeedbackBuilder: (context, column) => Material(
            color: Colors.transparent,
            child: Container(
              width: _widths[column.columnName],
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryColor),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Text(
                _title(column.columnName),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          columns: _columnOrder.map(_buildColumn).toList(growable: false),
        ),
      ),
    );
  }

  GridColumn _buildColumn(String key) {
    return GridColumn(
      columnName: key,
      width: _widths[key]!,
      minimumWidth: key == 'actions' ? 165 : 115,
      allowFiltering: key != 'actions',
      allowSorting: key != 'actions',
      label: _ItemsTrackerHeader(
        title: _title(key),
        color: _headerColor(key),
        alignLeft: const {
          'item_name',
          'supplier',
          'company',
          'item_status',
          'inventory_note',
          'status_updated_to',
          'last_activity',
          'latest_comment',
        }.contains(key),
      ),
    );
  }

  static String _title(String key) => switch (key) {
    'escalated_date' => 'ESCALATED DATE',
    'item_code' => 'ITEM CODE',
    'item_name' => 'ITEM NAME',
    'category' => 'CATEGORY',
    'supplier' => 'SUPPLIER',
    'company' => 'COMPANY',
    'item_status' => 'ITEM STATUS',
    'unit_cost' => 'ITEM COST',
    'inventory_note' => 'NOTES & REASON',
    'required_qty' => 'QTY REQUIRED ACTION',
    'required_value' => 'VALUE REQUIRED ACTION',
    'follow_up' => 'TO FOLLOW UP BY',
    'status_updated_to' => 'STATUS UPDATED TO',
    'last_activity' => 'LAST ACTION / FOLLOW-UP',
    'action_date' => 'ACTION DATE',
    'case_status' => 'STATUS',
    'latest_comment' => 'LATEST COMMENT',
    'comment_by' => 'COMMENT BY',
    'actions' => 'ACTIONS',
    _ => key,
  };

  static Color _headerColor(String key) {
    final index = _columnOrderDefault.indexOf(key);
    if (index <= 12) return const Color(0xfffff6b8);
    if (index <= 15) return const Color(0xffd8f2f8);
    if (index <= 17) return const Color(0xffefe8ff);
    return const Color(0xffe8eef4);
  }
}

class ItemsTrackerDataSource extends DataGridSource {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final NumberFormat _moneyFormat = NumberFormat('#,##0.00');
  static final NumberFormat _quantityFormat = NumberFormat('#,##0.###');

  List<ItemsTrackerRecord> _records;
  List<DataGridRow> _rows = const [];
  final Map<DataGridRow, ItemsTrackerRecord> _recordByRow = {};

  String role;
  ValueChanged<ItemsTrackerRecord> onEditInventory;
  ValueChanged<ItemsTrackerRecord> onAction;
  ValueChanged<ItemsTrackerRecord> onHistory;
  ValueChanged<ItemsTrackerRecord> onComment;

  ItemsTrackerDataSource({
    required List<ItemsTrackerRecord> records,
    required this.role,
    required this.onEditInventory,
    required this.onAction,
    required this.onHistory,
    required this.onComment,
  }) : _records = records {
    _rebuildRows();
  }

  void updateRecords(List<ItemsTrackerRecord> records) {
    _records = records;
    _rebuildRows();
    notifyListeners();
  }

  void _rebuildRows() {
    _recordByRow.clear();
    _rows = _records
        .map((record) {
          final row = DataGridRow(
            cells: [
              DataGridCell<DateTime>(
                columnName: 'escalated_date',
                value: record.escalatedDate,
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
                columnName: 'category',
                value: record.category,
              ),
              DataGridCell<String>(
                columnName: 'supplier',
                value: record.supplier,
              ),
              DataGridCell<String>(
                columnName: 'company',
                value: record.company,
              ),
              DataGridCell<String>(
                columnName: 'item_status',
                value: record.sourceItemStatus,
              ),
              DataGridCell<double?>(
                columnName: 'unit_cost',
                value: record.unitCost,
              ),
              DataGridCell<String>(
                columnName: 'inventory_note',
                value: record.inventoryNote,
              ),
              DataGridCell<double>(
                columnName: 'required_qty',
                value: record.requiredQty,
              ),
              DataGridCell<double?>(
                columnName: 'required_value',
                value: record.requiredValue,
              ),
              DataGridCell<String>(
                columnName: 'follow_up',
                value: record.followUpRole,
              ),
              DataGridCell<String>(
                columnName: 'status_updated_to',
                value: record.statusUpdatedTo,
              ),
              DataGridCell<String>(
                columnName: 'last_activity',
                value: record.displayedLastActivity,
              ),
              DataGridCell<DateTime?>(
                columnName: 'action_date',
                value: record.displayedLastActivityDate,
              ),
              DataGridCell<String>(
                columnName: 'case_status',
                value: record.caseStatus,
              ),
              DataGridCell<String>(
                columnName: 'latest_comment',
                value: record.latestComment,
              ),
              DataGridCell<String>(
                columnName: 'comment_by',
                value: record.commentByRole,
              ),
              const DataGridCell<String>(columnName: 'actions', value: ''),
            ],
          );
          _recordByRow[row] = record;
          return row;
        })
        .toList(growable: false);
  }

  @override
  List<DataGridRow> get rows => _rows;

  List<ItemsTrackerRecord> get visibleRecords => effectiveRows
      .map((row) => _recordByRow[row])
      .whereType<ItemsTrackerRecord>()
      .toList(growable: false);

  ItemsTrackerRecord? recordAtEffectiveIndex(int index) {
    final rows = effectiveRows;
    if (index < 0 || index >= rows.length) return null;
    return _recordByRow[rows[index]];
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final record = _recordByRow[row];
    final locked =
        record != null &&
        !record.canAct(role) &&
        !ItemsTrackerRoles.canEditInventoryFields(role);
    return DataGridRowAdapter(
      color: locked ? const Color(0xfff1f3f5) : Colors.white,
      cells: row
          .getCells()
          .map((cell) {
            if (record == null) return const SizedBox.shrink();
            switch (cell.columnName) {
              case 'follow_up':
                return Center(child: _RoleChip(role: record.followUpRole));
              case 'case_status':
                return Center(
                  child: _CaseStatusChip(status: record.caseStatus),
                );
              case 'actions':
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (ItemsTrackerRoles.canEditInventoryFields(role))
                      _GridActionButton(
                        tooltip: 'Edit inventory fields',
                        icon: Icons.edit_note_rounded,
                        color: const Color(0xffc38a00),
                        onPressed: () => onEditInventory(record),
                      ),
                    _GridActionButton(
                      tooltip: record.canAct(role)
                          ? 'Add action or follow-up'
                          : 'Assigned to ${ItemsTrackerRoles.label(record.followUpRole)}',
                      icon: record.canAct(role)
                          ? Icons.add_task_rounded
                          : Icons.lock_outline_rounded,
                      color: const Color(0xff0f8aa8),
                      onPressed: record.canAct(role)
                          ? () => onAction(record)
                          : null,
                    ),
                    _GridActionButton(
                      tooltip: 'Full history',
                      icon: Icons.history_rounded,
                      color: AppColors.primaryColor,
                      onPressed: () => onHistory(record),
                    ),
                    _GridActionButton(
                      tooltip: record.commentCount == 0
                          ? 'Add comment'
                          : '${record.commentCount} comments',
                      icon: Icons.mode_comment_outlined,
                      color: const Color(0xff7650b7),
                      onPressed: () => onComment(record),
                    ),
                  ],
                );
              case 'escalated_date':
              case 'action_date':
                final value = cell.value as DateTime?;
                return _TextCell(
                  value == null ? '—' : _dateFormat.format(value),
                  centered: true,
                  color: cell.columnName == 'escalated_date'
                      ? const Color(0xff8a6500)
                      : AppColors.secondaryColor,
                  bold: true,
                );
              case 'unit_cost':
              case 'required_value':
                final value = cell.value as num?;
                return _TextCell(
                  value == null ? '—' : _moneyFormat.format(value),
                  centered: true,
                  bold: true,
                );
              case 'required_qty':
                return _TextCell(
                  _quantityFormat.format(cell.value as num),
                  centered: true,
                  bold: true,
                );
              case 'last_activity':
                return _ActivityCell(record: record);
              case 'comment_by':
                final value = (cell.value ?? '').toString();
                return value.trim().isEmpty
                    ? const _TextCell('—', centered: true)
                    : Center(child: _RoleChip(role: value, compact: true));
              default:
                final value = (cell.value ?? '').toString();
                final leftAligned = const {
                  'item_name',
                  'supplier',
                  'company',
                  'item_status',
                  'inventory_note',
                  'status_updated_to',
                  'latest_comment',
                }.contains(cell.columnName);
                return _TextCell(
                  value.trim().isEmpty ? '—' : value,
                  centered: !leftAligned,
                  bold: cell.columnName == 'item_code',
                  color: cell.columnName == 'item_code'
                      ? AppColors.secondaryColor
                      : locked
                      ? const Color(0xff7b8790)
                      : AppColors.text,
                );
            }
          })
          .toList(growable: false),
    );
  }
}

class _ItemsTrackerHeader extends StatelessWidget {
  final String title;
  final Color color;
  final bool alignLeft;

  const _ItemsTrackerHeader({
    required this.title,
    required this.color,
    required this.alignLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        title,
        maxLines: 3,
        textAlign: alignLeft ? TextAlign.left : TextAlign.center,
        style: const TextStyle(
          color: AppColors.secondaryColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _TextCell extends StatelessWidget {
  final String value;
  final bool centered;
  final bool bold;
  final Color color;

  const _TextCell(
    this.value, {
    this.centered = false,
    this.bold = false,
    this.color = AppColors.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Tooltip(
        message: value == '—' ? '' : value,
        child: SelectableText(
          value,
          maxLines: 3,
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ActivityCell extends StatelessWidget {
  final ItemsTrackerRecord record;

  const _ActivityCell({required this.record});

  @override
  Widget build(BuildContext context) {
    final text = record.displayedLastActivity;
    final fallback = record.lastActionBody.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                fallback ? Icons.redo_rounded : Icons.task_alt_rounded,
                size: 15,
                color: fallback
                    ? const Color(0xff8a61c2)
                    : const Color(0xff0f8f78),
              ),
              const SizedBox(width: 6),
              Text(
                fallback ? 'FOLLOW-UP' : 'ACTION',
                style: TextStyle(
                  color: fallback
                      ? const Color(0xff7650b7)
                      : const Color(0xff087763),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (record.displayedLastActivityRole.trim().isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  '• ${ItemsTrackerRoles.label(record.displayedLastActivityRole).toUpperCase()}',
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            text.trim().isEmpty ? 'No activity yet' : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  final bool compact;

  const _RoleChip({required this.role, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final normalized = ItemsTrackerRoles.normalize(role);
    final color = switch (normalized) {
      ItemsTrackerRoles.inventory => const Color(0xffb77b00),
      ItemsTrackerRoles.purchase => const Color(0xff087e9b),
      ItemsTrackerRoles.category => const Color(0xff7650b7),
      _ => AppColors.subText,
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 11,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Text(
        ItemsTrackerRoles.label(role).toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CaseStatusChip extends StatelessWidget {
  final String status;

  const _CaseStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ItemsTrackerCaseStatuses.pending => const Color(0xffd4770a),
      ItemsTrackerCaseStatuses.inProgress => const Color(0xff087e9b),
      ItemsTrackerCaseStatuses.resolved => const Color(0xff0f8f78),
      ItemsTrackerCaseStatuses.closed => const Color(0xff596775),
      _ => AppColors.subText,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ItemsTrackerCaseStatuses.label(status).toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _GridActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _GridActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 19,
          color: onPressed == null ? const Color(0xffaab2b9) : color,
        ),
      ),
    );
  }
}
