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

typedef ItemsTrackerStatusChanged =
    Future<bool> Function(ItemsTrackerRecord record, String statusUpdatedTo);
typedef ItemsTrackerCaseStatusChanged =
    Future<bool> Function(ItemsTrackerRecord record, String trackerStatus);

class ItemsTrackerGrid extends StatefulWidget {
  final ItemsTrackerGridController controller;
  final List<ItemsTrackerRecord> records;
  final String role;
  final List<String> statusOptions;
  final ItemsTrackerStatusChanged onStatusUpdatedToChanged;
  final ItemsTrackerCaseStatusChanged onTrackerStatusChanged;
  final ValueChanged<ItemsTrackerRecord> onEditInventory;
  final ValueChanged<ItemsTrackerRecord> onAction;
  final ValueChanged<ItemsTrackerRecord> onHistory;
  final ValueChanged<ItemsTrackerRecord> onAttachment;
  final ValueChanged<ItemsTrackerRecord> onComment;

  const ItemsTrackerGrid({
    super.key,
    required this.controller,
    required this.records,
    required this.role,
    required this.statusOptions,
    required this.onStatusUpdatedToChanged,
    required this.onTrackerStatusChanged,
    required this.onEditInventory,
    required this.onAction,
    required this.onHistory,
    required this.onAttachment,
    required this.onComment,
  });

  @override
  State<ItemsTrackerGrid> createState() => _ItemsTrackerGridState();
}

class _ItemsTrackerGridState extends State<ItemsTrackerGrid> {
  static const _initialWidths = <String, double>{
    'escalated_date': 138,
    'item_code': 138,
    'item_name': 300,
    'inventory_note': 285,
    'required_qty': 130,
    'required_value': 150,
    'status_updated_to': 245,
    'follow_up': 150,

    'case_status': 145,
    'last_action': 450,
    'action_date': 138,
    'latest_comment': 285,
    'comment_by': 160,
    'actions': 190,
    'category': 160,
    'supplier': 225,
    'company': 190,
    'item_status': 205,
    'unit_cost': 130,
  };

  static const _columnOrderDefault = <String>[
    // Item info
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

    // Workflow
    'status_updated_to',
    'follow_up',

    'case_status',

    // Activity
    'last_action',
    'action_date',
    'latest_comment',
    'comment_by',

    // Controls
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
      statusOptions: widget.statusOptions,
      onStatusUpdatedToChanged: widget.onStatusUpdatedToChanged,
      onTrackerStatusChanged: widget.onTrackerStatusChanged,
      onEditInventory: widget.onEditInventory,
      onAction: widget.onAction,
      onHistory: widget.onHistory,
      onAttachment: widget.onAttachment,
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
      ..onStatusUpdatedToChanged = widget.onStatusUpdatedToChanged
      ..onTrackerStatusChanged = widget.onTrackerStatusChanged
      ..onEditInventory = widget.onEditInventory
      ..onAction = widget.onAction
      ..onHistory = widget.onHistory
      ..onAttachment = widget.onAttachment
      ..onComment = widget.onComment;

    if (!identical(oldWidget.statusOptions, widget.statusOptions)) {
      _source.updateStatusOptions(widget.statusOptions);
    }

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
    return ColoredBox(
      color: const Color(0xfff8fafc),
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbColor: const WidgetStatePropertyAll(Color(0xff668b99)),
          trackColor: const WidgetStatePropertyAll(Color(0xffedf2f5)),
          thickness: const WidgetStatePropertyAll(10),
          radius: const Radius.circular(12),
          thumbVisibility: const WidgetStatePropertyAll(true),
          trackVisibility: const WidgetStatePropertyAll(true),
        ),
        child: SfDataGridTheme(
          data: const SfDataGridThemeData(
            headerColor: Color(0xfff6f9fb),
            gridLineColor: Color(0xffcfdde3),
            selectionColor: Color(0xffeaf5f7),
            filterIconColor: Color(0xff456d7a),
            sortIconColor: Color(0xff27798b),
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
            rowHeight: 108,
            headerRowHeight: 66,
            selectionMode: SelectionMode.single,
            navigationMode: GridNavigationMode.cell,
            stackedHeaderRows: _buildStackedHeaders(),
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
            onFilterChanged: (_) {
              widget.controller._updateVisible(_source.visibleRecords);
            },
            onColumnSortChanged: (_, _) {
              widget.controller._updateVisible(_source.visibleRecords);
            },
            onColumnResizeUpdate: (details) {
              setState(() {
                _widths[details.column.columnName] = details.width;
              });
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
            columnDragFeedbackBuilder: (context, column) {
              return Material(
                color: Colors.transparent,
                child: Container(
                  width: _widths[column.columnName],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xff3d8797),
                      width: 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x24000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Text(
                    _title(column.columnName),
                    style: const TextStyle(
                      color: Color(0xff233f4b),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
            columns: _columnOrder.map(_buildColumn).toList(growable: false),
          ),
        ),
      ),
    );
  }

  List<StackedHeaderRow> _buildStackedHeaders() {
    return [
      StackedHeaderRow(
        cells: [
          StackedHeaderCell(
            columnNames: const [
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
            ],
            child: const _StackedHeaderLabel(
              label: 'Item info',
              icon: Icons.inventory_2_outlined,
              background: Color(0xffe7f2f7),
              foreground: Color(0xff285c70),
            ),
          ),
          StackedHeaderCell(
            columnNames: const [
              'status_updated_to',
              'follow_up',

              'case_status',
            ],
            child: const _StackedHeaderLabel(
              label: 'Workflow',
              icon: Icons.account_tree_outlined,
              background: Color(0xffe5f5f1),
              foreground: Color(0xff276c5c),
            ),
          ),
          StackedHeaderCell(
            columnNames: const [
              'last_action',
              'action_date',
              'latest_comment',
              'comment_by',
            ],
            child: const _StackedHeaderLabel(
              label: 'Activity',
              icon: Icons.timeline_rounded,
              background: Color(0xfff0eafa),
              foreground: Color(0xff67517d),
            ),
          ),
          StackedHeaderCell(
            columnNames: const ['actions'],
            child: const _StackedHeaderLabel(
              label: 'Controls',
              icon: Icons.tune_rounded,
              background: Color(0xffedf1f5),
              foreground: Color(0xff526573),
            ),
          ),
        ],
      ),
    ];
  }

  GridColumn _buildColumn(String key) {
    return GridColumn(
      columnName: key,
      width: _widths[key]!,
      minimumWidth: key == 'actions' ? 170 : 112,
      allowFiltering: key != 'actions',
      allowSorting: key != 'actions',
      label: _ItemsTrackerHeader(
        title: _title(key),
        section: _sectionFor(key),
        alignLeft: false,
      ),
    );
  }

  static String _title(String key) => switch (key) {
    'escalated_date' => 'Escalated date',
    'item_code' => 'Item code',
    'item_name' => 'Item name',
    'inventory_note' => 'Notes & reason',
    'required_qty' => 'Qty required',
    'required_value' => 'Value required',
    'status_updated_to' => 'Status updated to',
    'follow_up' => 'Follow-up team',

    'case_status' => 'Tracker Status',
    'last_action' => 'Last action / Follow-up',
    'action_date' => 'Activity date',
    'latest_comment' => 'Latest comment',
    'comment_by' => 'Comment by',
    'actions' => 'Actions',
    'category' => 'Category',
    'supplier' => 'Supplier',
    'company' => 'Company',
    'item_status' => 'Item status',
    'unit_cost' => 'Item cost',
    _ => key,
  };

  static _GridSection _sectionFor(String key) {
    if (const {
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
    }.contains(key)) {
      return _GridSection.itemInfo;
    }

    if (const {'follow_up', 'status_updated_to', 'case_status'}.contains(key)) {
      return _GridSection.workflow;
    }

    if (const {
      'last_action',
      'action_date',
      'latest_comment',
      'comment_by',
    }.contains(key)) {
      return _GridSection.activity;
    }

    return _GridSection.controls;
  }
}

enum _GridSection { itemInfo, workflow, activity, controls }

extension _GridSectionStyle on _GridSection {
  Color get headerColor {
    return switch (this) {
      _GridSection.itemInfo => const Color(0xffeef6f9),
      _GridSection.workflow => const Color(0xffedf8f5),
      _GridSection.activity => const Color(0xfff6f1fb),
      _GridSection.controls => const Color(0xfff1f4f7),
    };
  }

  Color get bodyColor {
    return switch (this) {
      _GridSection.itemInfo => const Color(0xfffbfdfe),
      _GridSection.workflow => const Color(0xfffbfefd),
      _GridSection.activity => const Color(0xfffdfbff),
      _GridSection.controls => Colors.white,
    };
  }

  Color get accentColor {
    return switch (this) {
      _GridSection.itemInfo => const Color(0xff3d7f93),
      _GridSection.workflow => const Color(0xff39806f),
      _GridSection.activity => const Color(0xff775e8d),
      _GridSection.controls => const Color(0xff5f7380),
    };
  }
}

class ItemsTrackerDataSource extends DataGridSource {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final NumberFormat _moneyFormat = NumberFormat('#,##0.00');
  static final NumberFormat _quantityFormat = NumberFormat('#,##0.###');

  List<ItemsTrackerRecord> _records;
  List<DataGridRow> _rows = const [];

  final Map<DataGridRow, ItemsTrackerRecord> _recordByRow = {};
  final Map<String, int> _recordIndexById = {};

  String role;
  List<String> statusOptions;
  ItemsTrackerStatusChanged onStatusUpdatedToChanged;
  ItemsTrackerCaseStatusChanged onTrackerStatusChanged;
  ValueChanged<ItemsTrackerRecord> onEditInventory;
  ValueChanged<ItemsTrackerRecord> onAction;
  ValueChanged<ItemsTrackerRecord> onHistory;
  ValueChanged<ItemsTrackerRecord> onAttachment;
  ValueChanged<ItemsTrackerRecord> onComment;

  ItemsTrackerDataSource({
    required List<ItemsTrackerRecord> records,
    required this.role,
    required this.statusOptions,
    required this.onStatusUpdatedToChanged,
    required this.onTrackerStatusChanged,
    required this.onEditInventory,
    required this.onAction,
    required this.onHistory,
    required this.onAttachment,
    required this.onComment,
  }) : _records = records {
    _rebuildRows();
  }

  void updateStatusOptions(List<String> options) {
    statusOptions = options;
    notifyListeners();
  }

  void updateRecords(List<ItemsTrackerRecord> records) {
    _records = records;
    _rebuildRows();
    notifyListeners();
  }

  void _rebuildRows() {
    _recordByRow.clear();
    _recordIndexById.clear();

    final builtRows = <DataGridRow>[];

    for (var index = 0; index < _records.length; index++) {
      final record = _records[index];

      _recordIndexById[record.id] = index;

      // IMPORTANT:
      // The cell order must exactly match _columnOrderDefault.
      // SfDataGrid renders DataGridRowAdapter cells positionally, so any
      // difference between the grid column order and this list places values
      // under the wrong headers.
      final row = DataGridRow(
        cells: [
          DataGridCell<DateTime>(
            columnName: 'escalated_date',
            value: record.escalatedDate,
          ),
          DataGridCell<String>(columnName: 'item_code', value: record.itemCode),
          DataGridCell<String>(columnName: 'item_name', value: record.itemName),
          DataGridCell<String>(columnName: 'category', value: record.category),
          DataGridCell<String>(columnName: 'supplier', value: record.supplier),
          DataGridCell<String>(columnName: 'company', value: record.company),
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
            columnName: 'status_updated_to',
            value: record.statusUpdatedTo,
          ),
          DataGridCell<String>(
            columnName: 'follow_up',
            value: record.followUpRole,
          ),

          DataGridCell<String>(
            columnName: 'case_status',
            value: record.caseStatus,
          ),
          DataGridCell<String>(
            columnName: 'last_action',
            value: record.displayedLastAction,
          ),
          DataGridCell<DateTime?>(
            columnName: 'action_date',
            value: record.displayedLastActionDate,
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
      builtRows.add(row);
    }

    _rows = builtRows;
  }

  @override
  List<DataGridRow> get rows => _rows;

  List<ItemsTrackerRecord> get visibleRecords => effectiveRows
      .map((row) => _recordByRow[row])
      .whereType<ItemsTrackerRecord>()
      .toList(growable: false);

  ItemsTrackerRecord? recordAtEffectiveIndex(int index) {
    final visibleRows = effectiveRows;

    if (index < 0 || index >= visibleRows.length) {
      return null;
    }

    return _recordByRow[visibleRows[index]];
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final record = _recordByRow[row];

    if (record == null) {
      return DataGridRowAdapter(cells: const [SizedBox.shrink()]);
    }

    final rowIndex = _recordIndexById[record.id] ?? 0;
    final completed = record.caseStatus == ItemsTrackerCaseStatuses.done;

    return DataGridRowAdapter(
      color: rowIndex.isEven ? Colors.white : const Color(0xfffbfcfd),
      cells: row
          .getCells()
          .map((cell) {
            final section = _sectionForColumn(cell.columnName);

            Widget child;

            switch (cell.columnName) {
              case 'escalated_date':
                child = _DateCell(
                  value: cell.value as DateTime?,
                  formatter: _dateFormat,
                  emphasized: true,
                );
                break;

              case 'item_code':
                child = _CodeCell(value: record.itemCode);
                break;

              case 'item_name':
                child = _ItemNameCell(
                  name: record.itemName,
                  category: record.category,
                );
                break;

              case 'inventory_note':
                child = _ReasonCell(
                  value: record.inventoryNote,
                  itemCode: record.itemCode,
                  itemName: record.itemName,
                );
                break;

              case 'required_qty':
                child = _NumberCell(
                  value: _quantityFormat.format(record.requiredQty),
                  label: 'Qty',
                );
                break;

              case 'required_value':
                child = _NumberCell(
                  value: record.requiredValue == null
                      ? '—'
                      : _moneyFormat.format(record.requiredValue),
                  label: 'AED',
                );
                break;

              case 'status_updated_to':
                if (ItemsTrackerRoles.canEditInventoryFields(role)) {
                  child = _StatusUpdatedToDropdown(
                    key: ValueKey(
                      'status-${record.id}-${record.statusUpdatedTo}-${record.rowVersion}',
                    ),
                    record: record,
                    options: statusOptions,
                    onChanged: (value) {
                      return onStatusUpdatedToChanged(record, value);
                    },
                  );
                } else {
                  child = _ReadOnlyStatusUpdatedTo(
                    value: record.statusUpdatedTo,
                  );
                }
                break;
              case 'follow_up':
                child = Center(child: _RoleChip(role: record.followUpRole));
                break;

              case 'case_status':
                child = role == ItemsTrackerRoles.inventory
                    ? _TrackerStatusDropdown(
                        key: ValueKey(
                          'tracker-status-${record.id}-${record.caseStatus}-${record.rowVersion}',
                        ),
                        record: record,
                        onChanged: (value) =>
                            onTrackerStatusChanged(record, value),
                      )
                    : Center(child: _CaseStatusChip(status: record.caseStatus));
                break;

              case 'last_action':
                child = _LastActionCell(
                  record: record,
                  onTap: () => onHistory(record),
                  onAttachmentTap: () => onAttachment(record),
                );
                break;

              case 'action_date':
                child = _DateCell(
                  value: record.displayedLastActionDate,
                  formatter: _dateFormat,
                );
                break;

              case 'latest_comment':
                child = _CommentCell(value: record.latestComment);
                break;

              case 'comment_by':
                final value = record.commentByRole.trim();
                child = value.isEmpty
                    ? const _PlainTextCell(
                        value: '—',
                        centered: true,
                        muted: true,
                      )
                    : Center(
                        child: _ActorIdentity(
                          role: value,
                          name: record.commentByName,
                        ),
                      );
                break;

              case 'actions':
                child = _ActionsCell(
                  record: record,
                  role: role,
                  onEditInventory: onEditInventory,
                  onAction: onAction,
                  onHistory: onHistory,
                  onComment: onComment,
                );
                break;

              case 'unit_cost':
                child = _NumberCell(
                  value: record.unitCost == null
                      ? '—'
                      : _moneyFormat.format(record.unitCost),
                  label: 'AED',
                );
                break;

              case 'item_status':
                child = _FixedStatusCell(value: record.sourceItemStatus);
                break;

              case 'category':
              case 'supplier':
              case 'company':
                child = _PlainTextCell(
                  value: (cell.value ?? '').toString(),
                  muted: completed,
                );
                break;

              default:
                child = _PlainTextCell(
                  value: (cell.value ?? '').toString(),
                  muted: completed,
                );
            }

            return _SectionCellFrame(
              columnName: cell.columnName,
              section: section,
              child: child,
            );
          })
          .toList(growable: false),
    );
  }

  static _GridSection _sectionForColumn(String key) {
    if (const {
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
    }.contains(key)) {
      return _GridSection.itemInfo;
    }

    if (const {'follow_up', 'status_updated_to', 'case_status'}.contains(key)) {
      return _GridSection.workflow;
    }

    if (const {
      'last_action',
      'action_date',
      'latest_comment',
      'comment_by',
    }.contains(key)) {
      return _GridSection.activity;
    }

    return _GridSection.controls;
  }
}

class _StackedHeaderLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  const _StackedHeaderLabel({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: background,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 12.8,
              fontWeight: FontWeight.w800,
              letterSpacing: .15,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsTrackerHeader extends StatelessWidget {
  final String title;
  final _GridSection section;
  final bool alignLeft;

  const _ItemsTrackerHeader({
    required this.title,
    required this.section,
    required this.alignLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: section.headerColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xff213d49),
          fontSize: 12,
          height: 1.18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SectionCellFrame extends StatelessWidget {
  final String columnName;
  final _GridSection section;
  final Widget child;

  const _SectionCellFrame({
    required this.columnName,
    required this.section,
    required this.child,
  });

  bool get _isSectionEnd {
    return const {
      'required_value',
      'case_status',
      'comment_by',
      'actions',
    }.contains(columnName);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: section.bodyColor,
        border: Border(
          right: BorderSide(
            color: _isSectionEnd
                ? section.accentColor.withValues(alpha: .38)
                : const Color(0xffe2e9ed),
            width: _isSectionEnd ? 2 : 1,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _PlainTextCell extends StatelessWidget {
  final String value;
  final bool centered;
  final bool muted;
  final bool semibold;

  const _PlainTextCell({
    required this.value,
    this.centered = false,
    this.muted = false,
    this.semibold = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = value.trim().isEmpty ? '—' : value.trim();

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Tooltip(
        message: text == '—' ? '' : text,
        child: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: muted ? const Color(0xff748791) : const Color(0xff243d48),
            fontSize: 12.5,
            height: 1.32,
            fontWeight: semibold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  final DateTime? value;
  final DateFormat formatter;
  final bool emphasized;

  const _DateCell({
    required this.value,
    required this.formatter,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null ? '—' : formatter.format(value!);

    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: emphasized ? 11 : 6,
          vertical: emphasized ? 7 : 4,
        ),
        decoration: emphasized
            ? BoxDecoration(
                color: const Color(0xfffff0cf),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xffffd987)),
              )
            : null,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: emphasized
                ? const Color(0xff7f5814)
                : const Color(0xff3b5662),
            fontSize: 12,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CodeCell extends StatelessWidget {
  final String value;

  const _CodeCell({required this.value});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xffe6f3f7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xffc5e1e9)),
        ),
        child: Text(
          value.trim().isEmpty ? '—' : value.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xff21596a),
            fontSize: 11.7,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ItemNameCell extends StatelessWidget {
  final String name;
  final String category;

  const _ItemNameCell({required this.name, required this.category});

  @override
  Widget build(BuildContext context) {
    final cleanName = name.trim().isEmpty ? '—' : name.trim();

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Tooltip(
        message: cleanName == '—' ? '' : cleanName,
        child: Text(
          cleanName,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff18333f),
            fontSize: 13,
            height: 1.28,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ReasonCell extends StatelessWidget {
  final String value;
  final String itemCode;
  final String itemName;

  const _ReasonCell({
    required this.value,
    required this.itemCode,
    required this.itemName,
  });

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty;
    final text = empty ? 'No reason added' : value.trim();

    const textStyle = TextStyle(
      color: Color(0xff344b56),
      fontSize: 12.1,
      height: 1.25,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: textStyle),
            maxLines: 2,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: constraints.maxWidth);
          final showReadMore = !empty && painter.didExceedMaxLines;

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: empty
                    ? textStyle.copyWith(color: const Color(0xff7f9098))
                    : textStyle,
              ),
              if (showReadMore) ...[
                const SizedBox(height: 2),
                TextButton.icon(
                  key: ValueKey('read-more-$itemCode'),
                  onPressed: () => _showFullReasonDialog(
                    context: context,
                    itemCode: itemCode,
                    itemName: itemName,
                    reason: value.trim(),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xff087e9b),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_full_rounded, size: 12),
                  label: const Text('Read more'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

Future<void> _showFullReasonDialog({
  required BuildContext context,
  required String itemCode,
  required String itemName,
  required String reason,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
              decoration: const BoxDecoration(
                color: Color(0xffeaf6f8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.notes_rounded,
                      color: Color(0xff087e9b),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notes & reason',
                          style: TextStyle(
                            color: Color(0xff173247),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$itemCode · $itemName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff607985),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xfff8fafc),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xffd7e3e8)),
                  ),
                  child: SelectableText(
                    reason,
                    style: const TextStyle(
                      color: Color(0xff263f4a),
                      fontSize: 14,
                      height: 1.65,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NumberCell extends StatelessWidget {
  final String value;
  final String label;

  const _NumberCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xff203a46),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (value != '—') ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xff7f9098),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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

    final foreground = switch (normalized) {
      ItemsTrackerRoles.inventory => const Color(0xff8a650e),
      ItemsTrackerRoles.purchase => const Color(0xff12677c),
      ItemsTrackerRoles.category => const Color(0xff6f4f87),
      _ => const Color(0xff526873),
    };

    final background = switch (normalized) {
      ItemsTrackerRoles.inventory => const Color(0xfffff0bf),
      ItemsTrackerRoles.purchase => const Color(0xffdff2f6),
      ItemsTrackerRoles.category => const Color(0xffeee3f6),
      _ => const Color(0xffeaf0f3),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: foreground.withValues(alpha: .16)),
      ),
      child: Text(
        ItemsTrackerRoles.label(role),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: compact ? 11 : 13.7,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ActorIdentity extends StatelessWidget {
  final String role;
  final String name;

  const _ActorIdentity({required this.role, required this.name});

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim();
    if (displayName.isEmpty) {
      return _RoleChip(role: role, compact: true);
    }

    return Tooltip(
      message: '${ItemsTrackerRoles.label(role)} · $displayName',
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 5,
        runSpacing: 3,
        children: [
          _RoleChip(role: role, compact: true),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 118),
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff405a65),
                fontSize: 10.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaseStatusChip extends StatelessWidget {
  final String status;

  const _CaseStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();

    final foreground = switch (normalized) {
      ItemsTrackerCaseStatuses.pending => const Color(0xffa85e10),
      ItemsTrackerCaseStatuses.done => const Color(0xff2f7354),
      _ => const Color(0xff566872),
    };

    final background = switch (normalized) {
      ItemsTrackerCaseStatuses.pending => const Color(0xffffe6c4),
      ItemsTrackerCaseStatuses.done => const Color(0xffdff2e8),
      _ => const Color(0xffe8edf0),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        ItemsTrackerCaseStatuses.label(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TrackerStatusDropdown extends StatefulWidget {
  final ItemsTrackerRecord record;
  final Future<bool> Function(String value) onChanged;

  const _TrackerStatusDropdown({
    super.key,
    required this.record,
    required this.onChanged,
  });

  @override
  State<_TrackerStatusDropdown> createState() => _TrackerStatusDropdownState();
}

class _TrackerStatusDropdownState extends State<_TrackerStatusDropdown> {
  late String _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.record.caseStatus;
  }

  Future<void> _change(String value) async {
    if (_saving || value == _selected) return;
    final previous = _selected;
    setState(() {
      _selected = value;
      _saving = true;
    });
    final saved = await widget.onChanged(value);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!saved) _selected = previous;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
      child: PopupMenuButton<String>(
        enabled: !_saving,
        tooltip: 'Change Tracker Status',
        initialValue: _selected,
        onSelected: _change,
        itemBuilder: (context) => ItemsTrackerCaseStatuses.values
            .map(
              (value) => PopupMenuItem<String>(
                value: value,
                child: Row(
                  children: [
                    Icon(
                      value == ItemsTrackerCaseStatuses.done
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded,
                      color: value == ItemsTrackerCaseStatuses.done
                          ? const Color(0xff2f7354)
                          : const Color(0xffa85e10),
                    ),
                    const SizedBox(width: 10),
                    Text(ItemsTrackerCaseStatuses.label(value)),
                    const Spacer(),
                    if (value == _selected)
                      const Icon(Icons.check_rounded, size: 18),
                  ],
                ),
              ),
            )
            .toList(growable: false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _selected == ItemsTrackerCaseStatuses.done
                ? const Color(0xffdff2e8)
                : const Color(0xffffe6c4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _selected == ItemsTrackerCaseStatuses.done
                  ? const Color(0xff9bcdb4)
                  : const Color(0xffffc978),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_saving)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              else
                Icon(
                  _selected == ItemsTrackerCaseStatuses.done
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  size: 15,
                ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  ItemsTrackerCaseStatuses.label(_selected),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.arrow_drop_down_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusUpdatedToDropdown extends StatefulWidget {
  final ItemsTrackerRecord record;
  final List<String> options;
  final Future<bool> Function(String value) onChanged;

  const _StatusUpdatedToDropdown({
    super.key,
    required this.record,
    required this.options,
    required this.onChanged,
  });

  @override
  State<_StatusUpdatedToDropdown> createState() {
    return _StatusUpdatedToDropdownState();
  }
}

class _StatusUpdatedToDropdownState extends State<_StatusUpdatedToDropdown> {
  late String _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.record.statusUpdatedTo.trim();
  }

  @override
  void didUpdateWidget(covariant _StatusUpdatedToDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.record.statusUpdatedTo != widget.record.statusUpdatedTo &&
        !_saving) {
      _selected = widget.record.statusUpdatedTo.trim();
    }
  }

  List<String> get _effectiveOptions {
    final valuesByNormalized = <String, String>{};

    for (final raw in [
      ...widget.options,
      widget.record.statusUpdatedTo,
      widget.record.sourceItemStatus,
    ]) {
      final value = raw.trim();

      if (value.isEmpty) continue;

      valuesByNormalized.putIfAbsent(value.toLowerCase(), () => value);
    }

    final values = valuesByNormalized.values.toList(
      growable: false,
    )..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));

    return values;
  }

  Future<void> _change(String value) async {
    final next = value.trim();

    if (next.isEmpty || _saving) return;

    if (next.toLowerCase() == _selected.toLowerCase()) return;

    final previous = _selected;

    setState(() {
      _selected = next;
      _saving = true;
    });

    final saved = await widget.onChanged(next);

    if (!mounted) return;

    setState(() {
      _saving = false;

      if (!saved) {
        _selected = previous;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final options = _effectiveOptions;

    final selected = options.firstWhere(
      (value) => value.toLowerCase() == _selected.toLowerCase(),
      orElse: () => options.isEmpty ? '' : options.first,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: PopupMenuButton<String>(
        enabled: !_saving && options.isNotEmpty,
        tooltip: 'Change Status Updated To',
        initialValue: selected.isEmpty ? null : selected,
        onSelected: _change,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
        itemBuilder: (context) {
          return options
              .map((value) {
                final active = value.toLowerCase() == selected.toLowerCase();

                return PopupMenuItem<String>(
                  value: value,
                  height: 46,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        active
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 18,
                        color: active
                            ? const Color(0xff2e766c)
                            : const Color(0xff9aa8af),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          value,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xff2f4650),
                            fontSize: 12.3,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              })
              .toList(growable: false);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xfffffbef),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xffffd979), width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xffffedbd),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  size: 15,
                  color: Color(0xff956414),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  selected.isEmpty ? 'Select status' : selected,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff4f421f),
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              if (_saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              else
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Color(0xff8b6a24),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyStatusUpdatedTo extends StatelessWidget {
  final String value;

  const _ReadOnlyStatusUpdatedTo({required this.value});

  @override
  Widget build(BuildContext context) {
    final text = value.trim().isEmpty ? '—' : value.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 15,
            color: Color(0xff8798a0),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: text == '—' ? '' : text,
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff445e69),
                fontSize: 12,
                height: 1.28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FixedStatusCell extends StatelessWidget {
  final String value;

  const _FixedStatusCell({required this.value});

  @override
  Widget build(BuildContext context) {
    final text = value.trim().isEmpty ? '—' : value.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 15,
            color: Color(0xff8798a0),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: text == '—' ? '' : text,
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff405a65),
                fontSize: 12,
                height: 1.28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LastActionCell extends StatefulWidget {
  final ItemsTrackerRecord record;
  final VoidCallback onTap;
  final VoidCallback onAttachmentTap;

  const _LastActionCell({
    required this.record,
    required this.onTap,
    required this.onAttachmentTap,
  });

  @override
  State<_LastActionCell> createState() => _LastActionCellState();
}

class _LastActionCellState extends State<_LastActionCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.record.displayedLastActivity.trim();
    final activityRole = widget.record.displayedLastActivityRole.trim();
    final isFollowUp = widget.record.displayedLastActivityType == 'follow_up';
    final activityColor = isFollowUp
        ? const Color(0xff087e9b)
        : const Color(0xff2e8b72);
    final empty = text.isEmpty;

    return MouseRegion(
      cursor: empty ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: empty ? null : (_) => setState(() => _hovered = true),
      onExit: empty ? null : (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: empty ? null : widget.onTap,
          hoverColor: const Color(0xffeee8f7),
          splashColor: const Color(0xffe4d9f1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xfff6f1fb) : Colors.transparent,
              border: Border.all(
                color: _hovered ? const Color(0xffcbb8dc) : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      empty
                          ? Icons.horizontal_rule_rounded
                          : isFollowUp
                          ? Icons.redo_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 16,
                      color: empty ? const Color(0xff89979e) : activityColor,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      empty
                          ? 'No activity'
                          : isFollowUp
                          ? 'Follow-up'
                          : 'Action',
                      style: TextStyle(
                        color: empty ? const Color(0xff78878e) : activityColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (activityRole.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: _ActorIdentity(
                          role: activityRole,
                          name: widget.record.displayedLastActivityByName,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Tooltip(
                  message: empty ? '' : text,
                  child: Text(
                    empty ? 'No action or follow-up recorded yet' : text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: empty
                          ? const Color(0xff829198)
                          : const Color(0xff2b444f),
                      fontSize: 12.4,
                      height: 1.28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!empty) ...[
                  const SizedBox(height: 3),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _hovered ? 1 : .72,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.record.displayedLastActivityHasAttachment)
                          Tooltip(
                            message:
                                'Download ${widget.record.latestActivityAttachmentName}',
                            child: InkWell(
                              onTap: widget.onAttachmentTap,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xffeee8f8),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xffcdbce2),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.attach_file_rounded,
                                      size: 13,
                                      color: Color(0xff68449c),
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'Attached',
                                      style: TextStyle(
                                        color: Color(0xff68449c),
                                        fontSize: 10.2,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(
                                      Icons.download_rounded,
                                      size: 12,
                                      color: Color(0xff68449c),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (widget.record.displayedLastActivityHasAttachment)
                          const SizedBox(width: 9),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 14,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'View full activity history',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 10.8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
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

class _CommentCell extends StatelessWidget {
  final String value;

  const _CommentCell({required this.value});

  @override
  Widget build(BuildContext context) {
    final text = value.trim();
    final empty = text.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            empty
                ? Icons.chat_bubble_outline_rounded
                : Icons.chat_bubble_rounded,
            size: 16,
            color: empty ? const Color(0xff9aa7ad) : AppColors.secondaryColor,
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: empty ? '' : text,
            child: Text(
              empty ? 'No comments yet' : text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: empty
                    ? const Color(0xff829198)
                    : AppColors.secondaryColor,
                fontSize: 14,
                height: 1.28,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsCell extends StatelessWidget {
  final ItemsTrackerRecord record;
  final String role;
  final ValueChanged<ItemsTrackerRecord> onEditInventory;
  final ValueChanged<ItemsTrackerRecord> onAction;
  final ValueChanged<ItemsTrackerRecord> onHistory;
  final ValueChanged<ItemsTrackerRecord> onComment;

  const _ActionsCell({
    required this.record,
    required this.role,
    required this.onEditInventory,
    required this.onAction,
    required this.onHistory,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    final canEditInventory = ItemsTrackerRoles.canEditInventoryFields(role);
    final canAct = record.canAct(role);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (canEditInventory)
          _GridActionButton(
            tooltip: 'Edit inventory fields',
            icon: Icons.edit_outlined,
            color: const Color(0xffa56d12),
            background: const Color(0xfffff0cd),
            onPressed: () => onEditInventory(record),
          ),
        _GridActionButton(
          tooltip: canAct
              ? 'Add action or follow-up'
              : 'Assigned to ${ItemsTrackerRoles.label(record.followUpRole)}',
          icon: canAct ? Icons.add_task_rounded : Icons.lock_outline_rounded,
          color: const Color(0xff216f82),
          background: const Color(0xffe2f2f6),
          onPressed: canAct ? () => onAction(record) : null,
        ),
        _GridActionButton(
          tooltip: 'Full history',
          icon: Icons.history_rounded,
          color: const Color(0xff3c6878),
          background: const Color(0xffedf3f5),
          onPressed: () => onHistory(record),
        ),
        _GridActionButton(
          tooltip: record.commentCount == 0
              ? 'Add comment'
              : '${record.commentCount} comments',
          icon: Icons.chat_bubble_outline_rounded,
          color: const Color(0xff6d5282),
          background: const Color(0xffefe7f5),
          badge: record.commentCount,
          onPressed: () => onComment(record),
        ),
      ],
    );
  }
}

class _GridActionButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onPressed;
  final int badge;

  const _GridActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.background,
    required this.onPressed,
    this.badge = 0,
  });

  @override
  State<_GridActionButton> createState() {
    return _GridActionButtonState();
  }
}

class _GridActionButtonState extends State<_GridActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: Tooltip(
        message: widget.tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 38,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: !enabled
                    ? const Color(0xfff0f3f5)
                    : _hovered
                    ? widget.background.withValues(alpha: .72)
                    : widget.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: enabled
                      ? widget.color.withValues(alpha: .14)
                      : const Color(0xffe0e5e8),
                ),
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: widget.onPressed,
                icon: Icon(
                  widget.icon,
                  size: 18,
                  color: enabled ? widget.color : const Color(0xffadb7bc),
                ),
              ),
            ),
            if (widget.badge > 0)
              Positioned(
                right: -1,
                top: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xff6b4e7b),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.badge > 99 ? '99+' : '${widget.badge}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
