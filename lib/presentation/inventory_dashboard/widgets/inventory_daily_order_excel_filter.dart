import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../domain/entities/daily_order_query.dart';
import 'inventory_daily_order_filter.dart';

typedef DailyOrderFilterAction = ({
  DailyOrderColumnFilter? filter,
  bool? ascending,
});

class InventoryDailyOrderExcelFilter extends StatefulWidget {
  const InventoryDailyOrderExcelFilter({
    super.key,
    required this.title,
    required this.field,
    required this.initial,
    required this.ascending,
    required this.loadValues,
  });

  final String title;
  final DailyOrderField field;
  final DailyOrderColumnFilter? initial;
  final bool? ascending;
  final Future<DailyOrderFilterValues> Function(String lookup, String? after)
  loadValues;

  @override
  State<InventoryDailyOrderExcelFilter> createState() =>
      _InventoryDailyOrderExcelFilterState();
}

class _InventoryDailyOrderExcelFilterState
    extends State<InventoryDailyOrderExcelFilter> {
  final _search = TextEditingController();
  final _options = <String?>[];
  late final Set<String?> _selection;
  late bool _exclude;
  Timer? _debounce;
  int _request = 0;
  String? _next;
  bool _loading = true;
  bool _failed = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _selection = {...?widget.initial?.values};
    _exclude = widget.initial?.values == null || widget.initial!.excludeValues;
    unawaited(_loadValues());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _request++;
    setState(() {
      _options.clear();
      _next = null;
      _failed = false;
      _loading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 250), _loadValues);
  }

  Future<void> _loadValues({bool more = false}) async {
    _debounce?.cancel();
    final request = ++_request;
    final after = more ? _next : null;
    setState(() {
      _failed = false;
      _loading = true;
    });
    try {
      final result = await widget.loadValues(_search.text.trim(), after);
      if (!mounted || request != _request) return;
      setState(() {
        if (!more) _options.clear();
        _options.addAll(result.values);
        _next = result.next;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      debugPrint('Daily Order filter values: $error');
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool _checked(String? value) => _exclude != _selection.contains(value);

  void _setChecked(String? value, bool checked) {
    if (checked == _exclude) {
      _selection.remove(value);
    } else {
      _selection.add(value);
    }
  }

  void _toggleAll(bool checked, bool shownOnly) {
    setState(() {
      _changed = true;
      if (shownOnly) {
        for (final value in _options) {
          _setChecked(value, checked);
        }
      } else {
        _exclude = checked;
        _selection.clear();
      }
    });
  }

  String _label(String? value) {
    if (value == null || value.isEmpty) return '(Blanks)';
    if (widget.field.column == 'branch') {
      return StoreBranchIdentityRegistry.displayName(value);
    }
    if (widget.field.type == DailyOrderFieldType.boolean) {
      return value == 'true' ? 'Yes' : 'No';
    }
    if (widget.field.type == DailyOrderFieldType.number &&
        value.contains('.')) {
      return value
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return value;
  }

  Future<void> _advanced() async {
    final result = await showDialog<DailyOrderColumnFilter>(
      context: context,
      builder: (context) => InventoryDailyOrderFilter(
        title: widget.title,
        field: widget.field,
        initial: widget.initial?.values == null ? widget.initial : null,
      ),
    );
    if (mounted && result != null) _finish(filter: result);
  }

  void _finish({DailyOrderColumnFilter? filter, bool? ascending}) {
    Navigator.pop<DailyOrderFilterAction>(context, (
      filter: filter,
      ascending: ascending,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final searching = _search.text.trim().isNotEmpty;
    final checkedCount = _options.where(_checked).length;
    final bool? allChecked = searching
        ? checkedCount == 0
              ? false
              : checkedCount == _options.length
              ? true
              : null
        : _selection.isEmpty
        ? _exclude
        : null;
    final canApply = _changed && (_exclude || _selection.isNotEmpty);
    final advancedLabel = switch (widget.field.type) {
      DailyOrderFieldType.text => 'Text filters',
      DailyOrderFieldType.number => 'Number filters',
      DailyOrderFieldType.date => 'Date filters',
      DailyOrderFieldType.boolean => 'Advanced filters',
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: 14,
      shadowColor: const Color(0x50142A46),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 8, 5, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_alt_outlined,
                  size: 18,
                  color: Color(0xFF12676B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF17354D),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close filter',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(child: _sortButton(true)),
                const SizedBox(width: 6),
                Expanded(child: _sortButton(false)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(child: _menuAction(advancedLabel, _advanced)),
                Expanded(
                  child: _menuAction(
                    'Clear filter',
                    widget.initial?.isActive == true
                        ? () => _finish(
                            filter: DailyOrderColumnFilter(
                              const [],
                              matchAny: false,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _search,
              onChanged: _searchChanged,
              onSubmitted: (_) => unawaited(_loadValues()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search values',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: !searching
                    ? null
                    : IconButton(
                        tooltip: 'Clear value search',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _search.clear();
                          _searchChanged('');
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF2F6FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            tristate: true,
            value: allChecked,
            title: Text(searching ? 'Select all shown' : 'Select all'),
            onChanged: searching && _options.isEmpty
                ? null
                : (_) => _toggleAll(allChecked != true, searching),
          ),
          const Divider(height: 1),
          Expanded(child: _buildOptions()),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: canApply
                      ? () => _finish(
                          filter: DailyOrderColumnFilter.values(
                            _selection,
                            excludeValues: _exclude,
                          ),
                        )
                      : null,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortButton(bool ascending) {
    final label = widget.field.type == DailyOrderFieldType.text
        ? (ascending ? 'A to Z' : 'Z to A')
        : (ascending ? 'Ascending' : 'Descending');
    return OutlinedButton.icon(
      onPressed: () => _finish(ascending: ascending),
      icon: Icon(
        ascending ? Icons.arrow_upward : Icons.arrow_downward,
        size: 15,
      ),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        backgroundColor: widget.ascending == ascending
            ? const Color(0xFFEAF5F3)
            : null,
      ),
    );
  }

  Widget _menuAction(String label, VoidCallback? onPressed) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      textStyle: const TextStyle(fontSize: 12),
    ),
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  Widget _buildOptions() {
    if (_options.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_options.isEmpty && !_failed) {
      return const Center(child: Text('No matching values'));
    }
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: StoreBranchIdentityRegistry.groups,
      builder: (context, _, _) => ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _options.length + (_next != null || _failed ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _options.length) {
            return Center(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: () => _loadValues(more: _options.isNotEmpty),
                      child: Text(
                        _failed ? 'Retry loading values' : 'Show more values',
                      ),
                    ),
            );
          }
          final value = _options[index];
          final label = _label(value);
          return CheckboxListTile(
            key: ValueKey(value),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Tooltip(
              message: label,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            value: _checked(value),
            onChanged: (checked) => setState(() {
              _changed = true;
              _setChecked(value, checked == true);
            }),
          );
        },
      ),
    );
  }
}
