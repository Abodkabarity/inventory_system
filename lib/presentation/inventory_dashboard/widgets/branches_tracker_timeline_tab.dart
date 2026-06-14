import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/additional_analysis/glass_container.dart';

class _SourceMeta {
  final String label;
  final Color color;
  final IconData icon;

  const _SourceMeta(this.label, this.color, this.icon);
}

const _sourceMeta = <String, _SourceMeta>{
  'order_edits': _SourceMeta(
    'Order Edit',
    Color(0xff3B82F6),
    Icons.edit_rounded,
  ),
  'max_adj': _SourceMeta(
    'Max Adj Active',
    Color(0xffF97316),
    Icons.tune_rounded,
  ),
  'max_adj_log': _SourceMeta(
    'Max Adj History',
    Color(0xffF59E0B),
    Icons.history_rounded,
  ),
  'mismatch_log': _SourceMeta(
    'Mismatch History',
    Color(0xffEF4444),
    Icons.warning_amber_rounded,
  ),
  'stk_mismatch': _SourceMeta(
    'Mismatch Active',
    Color(0xffDC2626),
    Icons.report_problem_rounded,
  ),
};

_SourceMeta _meta(String? table) {
  return _sourceMeta[table ?? ''] ??
      const _SourceMeta('Change', Color(0xff94A3B8), Icons.circle_outlined);
}

class BranchesTrackerTimelineTab extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final bool loading;

  const BranchesTrackerTimelineTab({
    super.key,
    required this.rows,
    required this.loading,
  });

  @override
  State<BranchesTrackerTimelineTab> createState() =>
      _BranchesTrackerTimelineTabState();
}

class _BranchesTrackerTimelineTabState
    extends State<BranchesTrackerTimelineTab> {
  String _search = '';
  String _branchFilter = 'ALL';
  String _typeFilter = 'ALL';
  int _page = 0;

  static const int _pageSize = 50;

  List<String> get _branches {
    final list =
        widget.rows
            .map((r) => (r['branch_name'] ?? '').toString())
            .where((e) => e.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return ['ALL', ...list];
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();

    return widget.rows.where((r) {
      final source = (r['source_table'] ?? '').toString();
      final branch = (r['branch_name'] ?? '').toString();

      final matchType = _typeFilter == 'ALL' || source == _typeFilter;
      final matchBranch = _branchFilter == 'ALL' || branch == _branchFilter;

      final text = [
        r['branch_name'],
        r['item_code'],
        r['item_name'],
        r['reason'],
        r['title'],
        r['change_type'],
        r['source_table'],
      ].join(' ').toLowerCase();

      return matchType && matchBranch && (q.isEmpty || text.contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xff06B6D4)),
      );
    }

    final filtered = _filtered;
    final pageCount = (filtered.length / _pageSize).ceil().clamp(1, 99999);
    final safePage = _page.clamp(0, pageCount - 1);

    final pageRows = filtered.isEmpty
        ? <Map<String, dynamic>>[]
        : filtered.sublist(
            safePage * _pageSize,
            (safePage * _pageSize + _pageSize).clamp(0, filtered.length),
          );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        onChanged: (v) {
                          setState(() {
                            _search = v;
                            _page = 0;
                          });
                        },
                        decoration: InputDecoration(
                          hintText:
                              'Search branch, item code, item name, reason...',
                          hintStyle: const TextStyle(color: Color(0xff94A3B8)),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xff94A3B8),
                          ),
                          filled: true,
                          fillColor: const Color(0xffF1F5F9),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _BranchDropdown(
                      value: _branchFilter,
                      items: _branches,
                      onChanged: (v) {
                        setState(() {
                          _branchFilter = v;
                          _page = 0;
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xffE2E8F0)),
                      ),
                      child: Text(
                        '${filtered.length} results',
                        style: const TextStyle(
                          color: Color(0xff64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TypeChip(
                      label: 'All',
                      count: widget.rows.length,
                      selected: _typeFilter == 'ALL',
                      color: const Color(0xff06B6D4),
                      onTap: () {
                        setState(() {
                          _typeFilter = 'ALL';
                          _page = 0;
                        });
                      },
                    ),
                    ...[
                      'order_edits',
                      'max_adj',
                      'max_adj_log',
                      'mismatch_log',
                      'stk_mismatch',
                    ].map((t) {
                      final m = _meta(t);
                      final count = widget.rows
                          .where((r) => r['source_table'] == t)
                          .length;

                      return _TypeChip(
                        label: m.label,
                        count: count,
                        selected: _typeFilter == t,
                        color: m.color,
                        onTap: () {
                          setState(() {
                            _typeFilter = t;
                            _page = 0;
                          });
                        },
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (filtered.isEmpty)
            const _EmptyState()
          else ...[
            GlassContainer(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xffF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 44),
                        SizedBox(width: 12),
                        Expanded(flex: 2, child: _ColHeader('Branch')),
                        Expanded(flex: 3, child: _ColHeader('Item')),
                        Expanded(flex: 2, child: _ColHeader('Title')),
                        SizedBox(width: 240, child: _ColHeader('Values')),
                        SizedBox(width: 140, child: _ColHeader('Date & Time')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...pageRows.map((r) => _ChangeRow(row: r)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Pagination(
              current: safePage,
              total: pageCount,
              filtered: filtered.length,
              pageSize: _pageSize,
              onChanged: (p) => setState(() => _page = p),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatefulWidget {
  final Map<String, dynamic> row;

  const _ChangeRow({required this.row});

  @override
  State<_ChangeRow> createState() => _ChangeRowState();
}

class _ChangeRowState extends State<_ChangeRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final meta = _meta(r['source_table']?.toString());

    final dt = DateTime.tryParse((r['changed_at'] ?? '').toString());
    final dateText = dt == null
        ? '-'
        : DateFormat('MMM d  hh:mm a').format(dt.toLocal());

    final value1Label = (r['value1_label'] ?? 'Value 1').toString();
    final value2Label = (r['value2_label'] ?? 'Value 2').toString();
    final value3Label = (r['value3_label'] ?? 'Value 3').toString();

    final value1 = r['value1'];
    final value2 = r['value2'];
    final value3 = r['value3'];

    final action = (r['change_type'] ?? '').toString().toLowerCase();
    final source = (r['source_table'] ?? '').toString();

    final isMismatchLog = source == 'mismatch_log';

    final oldSystem = r['old_system_value'];
    final newSystem = r['new_system_value'];
    final oldActual = r['old_actual_value'];
    final newActual = r['new_actual_value'];
    final oldDiff = r['old_diff_value'];
    final newDiff = r['new_diff_value'];

    final note = (r['reason'] ?? '').toString();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _expanded ? meta.color.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _expanded
              ? meta.color.withValues(alpha: 0.25)
              : const Color(0xffE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: meta.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(meta.icon, color: meta.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Text(
                      (r['branch_name'] ?? '-').toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xff1E293B),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (r['item_name'] ?? '-').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xff1E293B),
                          ),
                        ),
                        Text(
                          (r['item_code'] ?? '').toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xff94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (r['title'] ?? '').toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xff1E293B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            action.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: meta.color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: Row(
                      children: [
                        _ValBox(value1Label, value1, const Color(0xffEF4444)),
                        const SizedBox(width: 6),
                        _ValBox(value2Label, value2, Colors.green),
                        const SizedBox(width: 6),
                        _ValBox(value3Label, value3, const Color(0xff3B82F6)),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          dateText.split('  ').first,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xff1E293B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          dateText.contains('  ')
                              ? dateText.split('  ').last
                              : '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xff94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xff94A3B8),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xffF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xffE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _DetailBox(value1Label, value1, const Color(0xffEF4444)),
                      const SizedBox(width: 12),
                      _DetailBox(value2Label, value2, Colors.green),
                      const SizedBox(width: 12),
                      _DetailBox(value3Label, value3, const Color(0xff3B82F6)),
                      if ((r['changed_by'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(width: 20),
                        _DetailBox(
                          'Changed By',
                          r['changed_by'],
                          const Color(0xff8B5CF6),
                        ),
                      ],
                    ],
                  ),
                  if (isMismatchLog) ...[
                    const SizedBox(height: 14),
                    _MismatchDetails(
                      action: action,
                      oldSystem: oldSystem,
                      newSystem: newSystem,
                      oldActual: oldActual,
                      newActual: newActual,
                      oldDiff: oldDiff,
                      newDiff: newDiff,
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.notes_rounded,
                          size: 14,
                          color: Color(0xff94A3B8),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xff64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MismatchDetails extends StatelessWidget {
  final String action;
  final dynamic oldSystem;
  final dynamic newSystem;
  final dynamic oldActual;
  final dynamic newActual;
  final dynamic oldDiff;
  final dynamic newDiff;

  const _MismatchDetails({
    required this.action,
    required this.oldSystem,
    required this.newSystem,
    required this.oldActual,
    required this.newActual,
    required this.oldDiff,
    required this.newDiff,
  });

  @override
  Widget build(BuildContext context) {
    if (action == 'update') {
      return _MismatchPanel(
        title: 'Mismatch Update Details',
        icon: Icons.compare_arrows_rounded,
        color: const Color(0xffF97316),
        children: [
          _CompareLine(
            label: 'System Stock',
            oldValue: oldSystem,
            newValue: newSystem,
            color: const Color(0xffF97316),
          ),
          const SizedBox(width: 14),
          _CompareLine(
            label: 'Actual Stock',
            oldValue: oldActual,
            newValue: newActual,
            color: const Color(0xff06B6D4),
          ),
          const SizedBox(width: 14),
          _CompareLine(
            label: 'Diff',
            oldValue: oldDiff,
            newValue: newDiff,
            color: const Color(0xff3B82F6),
          ),
        ],
      );
    }

    if (action == 'add') {
      return _MismatchPanel(
        title: 'Mismatch Added',
        icon: Icons.add_circle_outline_rounded,
        color: const Color(0xff22C55E),
        children: [
          _SingleValueLine(
            label: 'New System',
            value: newSystem,
            color: const Color(0xffF97316),
          ),
          const SizedBox(width: 14),
          _SingleValueLine(
            label: 'New Actual',
            value: newActual,
            color: const Color(0xff06B6D4),
          ),
          const SizedBox(width: 14),
          _SingleValueLine(
            label: 'New Diff',
            value: newDiff,
            color: const Color(0xff3B82F6),
          ),
        ],
      );
    }

    if (action == 'delete') {
      return _MismatchPanel(
        title: 'Mismatch Deleted',
        icon: Icons.delete_outline_rounded,
        color: const Color(0xffEF4444),
        children: [
          _SingleValueLine(
            label: 'Old System',
            value: oldSystem,
            color: const Color(0xffF97316),
          ),
          const SizedBox(width: 14),
          _SingleValueLine(
            label: 'Old Actual',
            value: oldActual,
            color: const Color(0xff06B6D4),
          ),
          const SizedBox(width: 14),
          _SingleValueLine(
            label: 'Old Diff',
            value: oldDiff,
            color: const Color(0xff3B82F6),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _MismatchPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _MismatchPanel({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: children),
        ],
      ),
    );
  }
}

class _CompareLine extends StatelessWidget {
  final String label;
  final dynamic oldValue;
  final dynamic newValue;
  final Color color;

  const _CompareLine({
    required this.label,
    required this.oldValue,
    required this.newValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _boxDecoration(color),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _MiniValue(value: oldValue, color: const Color(0xffEF4444)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: Color(0xff94A3B8),
              ),
            ),
            _MiniValue(value: newValue, color: const Color(0xff22C55E)),
          ],
        ),
      ),
    );
  }
}

class _SingleValueLine extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;

  const _SingleValueLine({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _boxDecoration(color),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _MiniValue(value: value, color: color),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _boxDecoration(Color color) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: color.withValues(alpha: 0.18)),
  );
}

class _MiniValue extends StatelessWidget {
  final dynamic value;
  final Color color;

  const _MiniValue({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        _fmt(value),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.25)
                    : color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? Colors.white : color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _BranchDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xffF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xff64748B),
            size: 18,
          ),
          style: const TextStyle(
            color: Color(0xff1E293B),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e == 'ALL' ? 'All Branches' : e),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final int current;
  final int total;
  final int filtered;
  final int pageSize;
  final ValueChanged<int> onChanged;

  const _Pagination({
    required this.current,
    required this.total,
    required this.filtered,
    required this.pageSize,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final start = filtered == 0 ? 0 : current * pageSize + 1;
    final end = ((current + 1) * pageSize).clamp(0, filtered);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Showing $start-$end of $filtered',
          style: const TextStyle(color: Color(0xff64748B), fontSize: 13),
        ),
        const SizedBox(width: 24),
        _pageBtn(Icons.chevron_left, current > 0, () => onChanged(current - 1)),
        const SizedBox(width: 12),
        Text(
          '${current + 1} / $total',
          style: const TextStyle(
            color: Color(0xff1E293B),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        _pageBtn(
          Icons.chevron_right,
          current < total - 1,
          () => onChanged(current + 1),
        ),
      ],
    );
  }

  Widget _pageBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xffF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xffE2E8F0)),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? const Color(0xff64748B) : const Color(0xffCBD5E1),
        ),
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String text;

  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xff64748B),
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    );
  }
}

class _ValBox extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;

  const _ValBox(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
          ),
          Text(
            _fmt(value),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBox extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;

  const _DetailBox(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 2),
          Text(
            _fmt(value),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: Color(0xff94A3B8), size: 40),
            SizedBox(height: 16),
            Text(
              'No changes match your filters',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xff64748B),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Try adjusting the branch, type, or search term.',
              style: TextStyle(fontSize: 13, color: Color(0xff94A3B8)),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(dynamic v) {
  if (v == null) return '-';
  if (v is num) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
  return v.toString();
}
