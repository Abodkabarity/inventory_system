import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/items_tracker_column_filter.dart';
import '../../../domain/entities/items_tracker_record.dart';

Future<ItemsTrackerColumnFilter?> showItemsTrackerColumnFilter({
  required BuildContext context,
  required ItemsTrackerColumn column,
  required List<ItemsTrackerRecord> records,
  required ItemsTrackerColumnFilter? current,
}) {
  final box = context.findRenderObject() as RenderBox;
  final origin = box.localToGlobal(Offset.zero);
  final anchor = Rect.fromLTWH(
    origin.dx,
    origin.dy,
    box.size.width,
    box.size.height,
  );
  return showDialog<ItemsTrackerColumnFilter>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .12),
    builder: (_) => _ColumnFilterMenu(
      column: column,
      records: records,
      current: current,
      anchor: anchor,
    ),
  );
}

class _ColumnFilterMenu extends StatefulWidget {
  final ItemsTrackerColumn column;
  final List<ItemsTrackerRecord> records;
  final ItemsTrackerColumnFilter? current;
  final Rect anchor;
  const _ColumnFilterMenu({
    required this.column,
    required this.records,
    required this.current,
    required this.anchor,
  });
  @override
  State<_ColumnFilterMenu> createState() => _ColumnFilterMenuState();
}

class _ColumnFilterMenuState extends State<_ColumnFilterMenu> {
  final _search = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  late final Map<String, int> _counts;
  late final List<String> _values;
  Set<String>? _selected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _counts = {};
    for (final record in widget.records) {
      final value = widget.column.value(record);
      _counts[value] = (_counts[value] ?? 0) + 1;
    }
    // Retain saved choices even when another filter hides them.
    _values = {..._counts.keys, ...?widget.current?.selected}.toList()
      ..sort((a, b) {
        if (a.isEmpty) return b.isEmpty ? 0 : -1;
        if (b.isEmpty) return 1;
        return widget.column.isNumeric
            ? double.parse(a).compareTo(double.parse(b))
            : a.toLowerCase().compareTo(b.toLowerCase());
      });
    _selected = widget.current?.selected?.toSet();
    _min.text = widget.current?.minimum?.toString() ?? '';
    _max.text = widget.current?.maximum?.toString() ?? '';
  }

  @override
  void dispose() {
    _search.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  String _label(String value) => value.isEmpty
      ? '(Blanks)'
      : widget.column == ItemsTrackerColumn.cost
      ? 'AED ${NumberFormat('#,##0.00##').format(double.parse(value))}'
      : widget.column == ItemsTrackerColumn.quantity
      ? NumberFormat('#,##0.###').format(double.parse(value))
      : value;

  void _toggle(String value, bool selected) => setState(() {
    _selected ??= _values.toSet();
    if (selected) {
      _selected!.add(value);
    } else {
      _selected!.remove(value);
    }
  });

  void _apply() {
    final minimum = _min.text.trim().isEmpty
        ? null
        : double.tryParse(_min.text.trim().replaceAll(',', ''));
    final maximum = _max.text.trim().isEmpty
        ? null
        : double.tryParse(_max.text.trim().replaceAll(',', ''));
    if ((_min.text.trim().isNotEmpty &&
            (minimum == null || !minimum.isFinite)) ||
        (_max.text.trim().isNotEmpty &&
            (maximum == null || !maximum.isFinite))) {
      setState(() => _error = 'Enter a valid number.');
      return;
    }
    if (minimum != null && maximum != null && minimum > maximum) {
      setState(() => _error = 'Minimum must be less than or equal to maximum.');
      return;
    }
    Navigator.pop(
      context,
      ItemsTrackerColumnFilter(
        selected:
            _selected != null &&
                _selected!.containsAll(_values) &&
                _values.isNotEmpty
            ? null
            : _selected,
        minimum: minimum,
        maximum: maximum,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(380.0, size.width - 24);
    final height = math.min(
      widget.column.isNumeric ? 640.0 : 510.0,
      size.height - 40,
    );
    final left = (widget.anchor.right - width).clamp(
      12.0,
      math.max(12.0, size.width - width - 12),
    );
    final top = (widget.anchor.bottom + 6).clamp(
      20.0,
      math.max(20.0, size.height - height - 20),
    );
    final query = _search.text.trim().toLowerCase();
    final visible = _values
        .where((value) => _label(value).toLowerCase().contains(query))
        .toList();
    final checkedCount = visible
        .where((value) => _selected == null || _selected!.contains(value))
        .length;
    return Stack(
      children: [
        Positioned(
          left: left.toDouble(),
          top: top.toDouble(),
          width: width,
          height: height,
          child: Material(
            color: Colors.white,
            elevation: 14,
            shadowColor: const Color(0x33122d40),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
                  color: AppColors.backgroundWidget,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_alt_outlined,
                        size: 20,
                        color: AppColors.secondaryColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Filter ${widget.column.label.toLowerCase()}',
                          style: const TextStyle(
                            color: AppColors.secondaryColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 19),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    key: ValueKey('columnFilterSearch:${widget.column.name}'),
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search values…',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xfff5f8fb),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
                if (widget.column.isNumeric)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('columnFilterMin'),
                            controller: _min,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Minimum',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('columnFilterMax'),
                            controller: _max,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Maximum',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        tristate: true,
                        activeColor: AppColors.primaryColor,
                        value: checkedCount == 0
                            ? false
                            : checkedCount == visible.length
                            ? true
                            : null,
                        onChanged: visible.isEmpty
                            ? null
                            : (_) => setState(() {
                                if (query.isEmpty &&
                                    checkedCount != visible.length) {
                                  _selected = null;
                                } else {
                                  _selected ??= _values.toSet();
                                  if (checkedCount == visible.length) {
                                    _selected!.removeAll(visible);
                                  } else {
                                    _selected!.addAll(visible);
                                  }
                                }
                              }),
                      ),
                      Expanded(
                        child: Text(
                          query.isEmpty
                              ? 'Select all'
                              : 'Select search results',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        '${visible.length} values',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.subText,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (query.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey('columnFilterOnlyResults'),
                      onPressed: visible.isEmpty
                          ? null
                          : () => setState(() => _selected = visible.toSet()),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.secondaryColor,
                      ),
                      child: const Text(
                        'Select only these results',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(
                          child: Text(
                            'No matching values',
                            style: TextStyle(color: AppColors.subText),
                          ),
                        )
                      : ListView.builder(
                          key: const ValueKey('columnFilterValues'),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final value = visible[index];
                            return CheckboxListTile(
                              key: ValueKey('columnFilterValue:$value'),
                              dense: true,
                              activeColor: AppColors.primaryColor,
                              controlAffinity: ListTileControlAffinity.leading,
                              value:
                                  _selected == null ||
                                  _selected!.contains(value),
                              onChanged: (checked) =>
                                  _toggle(value, checked ?? false),
                              title: Tooltip(
                                message: _label(value),
                                child: Text(
                                  _label(value),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: value.isEmpty
                                        ? AppColors.subText
                                        : AppColors.secondaryColor,
                                  ),
                                ),
                              ),
                              secondary: Text(
                                '${_counts[value] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.subText,
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        key: const ValueKey('columnFilterClear'),
                        onPressed: () =>
                            Navigator.pop(context, ItemsTrackerColumnFilter()),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.secondaryColor,
                        ),
                        icon: const Icon(
                          Icons.filter_alt_off_outlined,
                          size: 16,
                        ),
                        label: const Text('Clear filter'),
                      ),
                      const Spacer(),
                      FilledButton(
                        key: const ValueKey('columnFilterApply'),
                        onPressed: _apply,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
