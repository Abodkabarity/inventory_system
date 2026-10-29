import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../core/utils/stock_vendor.dart';
import '../../../domain/entities/stock_management.dart';
import '../../../domain/entities/stock_mrn_receipt_history.dart';
import 'stock_catalog_visuals.dart';
import 'stock_receipt_quantity.dart';

/// Loads all receipt dates on expansion, keeping MRNs and expiries distinct.
class StockMrnReceipts extends StatefulWidget {
  final StockManagementItem item;
  final Future<StockMrnReceiptHistory> Function()? loadHistory;
  const StockMrnReceipts({super.key, required this.item, this.loadHistory});

  @override
  State<StockMrnReceipts> createState() => _StockMrnReceiptsState();
}

class _StockMrnReceiptsState extends State<StockMrnReceipts> {
  static const _ink = Color(0xFF243449);
  static const _muted = Color(0xFF697789);
  static const _line = Color(0xFFE8EDF2);
  static const _green = Color(0xFF26735D);
  final _vertical = ScrollController(), _horizontal = ScrollController();
  StockMrnReceiptHistory? _history;
  bool _loading = false, _failed = false, _expanded = false;
  int _generation = 0;

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StockMrnReceipts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.registerKey != widget.item.registerKey) {
      _generation++;
      _history = null;
      _loading = _failed = false;
    }
  }

  Future<void> _load() async {
    if (_loading || widget.loadHistory == null) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final history = await widget.loadHistory!();
      if (!mounted || generation != _generation) return;
      setState(() => _history = history);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final fullHistory = widget.loadHistory != null;
    final lines = _history?.lines ?? item.list('receipt_lines');
    if (!fullHistory && lines.isEmpty) return const SizedBox.shrink();
    final summary = stockMap(item.data['receipt_history_summary']);
    final hasSummary = fullHistory && summary.containsKey('mrn_count');
    final count =
        _history?.mrnCount ?? stockNumber(summary['mrn_count']).toInt();
    final dayCount =
        _history?.dayCount ?? stockNumber(summary['day_count']).toInt();
    final from = _history?.from ?? summary['from'];
    final through = _history?.through ?? summary['through'];
    final hasHistoryTotals = _history != null || hasSummary;
    final title = fullHistory
        ? 'MRN receipt history${hasHistoryTotals ? ' ($count)' : ''}'
        : 'MRN receipts (${item.number('receipt_count').toInt()})';
    final dates = hasHistoryTotals
        ? dayCount == 0
              ? 'No approved receipt dates'
              : '${catalogDate(from)} – ${catalogDate(through)} · $dayCount receipt dates'
        : fullHistory
        ? 'Latest receipt ${catalogDate(item.text('last_mrn_date'))} · View all receipts'
        : catalogDate(item.text('last_mrn_date'));
    final total =
        _history?.receivedQty ??
        (hasSummary
            ? stockNumber(summary['received_qty'])
            : item.number('received_quantity'));
    final showTotal = hasHistoryTotals || !fullHistory;
    final bonus =
        _history?.bonus ??
        (hasSummary ? stockNumber(summary['bonus']) : item.receiptBonus);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x041B3046),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          hoverColor: const Color(0xFFF4F7F9),
          splashColor: const Color(0x0A26735D),
          highlightColor: Colors.transparent,
          scrollbarTheme: ScrollbarThemeData(
            thumbColor: const WidgetStatePropertyAll(Color(0xFFB6C2CC)),
            thickness: const WidgetStatePropertyAll(5),
            radius: const Radius.circular(5),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final totalBadge = Tooltip(
              message: hasHistoryTotals
                  ? 'Total received across the complete receipt history'
                  : 'Total received on the latest MRN date',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F6F3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Total Qty ${catalogQty(total)}${bonus > 0 ? ' · Bonus ${catalogQty(bonus)}' : ''}',
                  style: const TextStyle(
                    color: _green,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
            return ExpansionTile(
              key: const ValueKey('mrn-receipt-lines'),
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              backgroundColor: Colors.white,
              collapsedBackgroundColor: Colors.white,
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F6F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: _green,
                  size: 21,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showTotal && !compact) ...[
                    totalBadge,
                    const SizedBox(width: 18),
                  ],
                  AnimatedRotation(
                    turns: _expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _muted,
                      size: 23,
                    ),
                  ),
                ],
              ),
              onExpansionChanged: (open) {
                setState(() => _expanded = open);
                if (open && _history == null) _load();
              },
              title: Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dates,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    if (showTotal && compact)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: totalBadge,
                      ),
                  ],
                ),
              ),
              children: [
                if (fullHistory && (_loading || (_history == null && !_failed)))
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(
                      color: _green,
                      backgroundColor: _line,
                    ),
                  )
                else if (_failed)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Could not load receipt history. Please retry.',
                            style: TextStyle(color: _muted),
                          ),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                else if (lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No approved MRN receipts found.',
                      style: TextStyle(color: _muted),
                    ),
                  )
                else ...[
                  const Divider(height: 1, color: _line),
                  const SizedBox(height: 12),
                  _table(lines),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.sort_rounded, size: 14, color: _muted),
                      const SizedBox(width: 6),
                      Text(
                        '${lines.length} receipt lines · Newest first',
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _table(List<Map<String, dynamic>> lines) =>
      ValueListenableBuilder<Map<String, String>>(
        valueListenable: StoreBranchIdentityRegistry.groups,
        builder: (context, _, _) => LayoutBuilder(
          builder: (context, constraints) {
            return Scrollbar(
              controller: _horizontal,
              thumbVisibility: true,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(constraints.maxWidth, 1080),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: Scrollbar(
                      controller: _vertical,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _vertical,
                        child: DataTable(
                          headingRowColor: const WidgetStatePropertyAll(
                            Color(0xFFF5F7F9),
                          ),
                          headingTextStyle: const TextStyle(
                            color: Color(0xFF536174),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          dataTextStyle: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                          headingRowHeight: 42,
                          dataRowMinHeight: 54,
                          dataRowMaxHeight: 54,
                          columnSpacing: 22,
                          horizontalMargin: 16,
                          dividerThickness: .6,
                          border: const TableBorder(
                            horizontalInside: BorderSide(
                              color: _line,
                              width: .6,
                            ),
                          ),
                          columns: [
                            for (final title in [
                              'MRN date',
                              'MRN number',
                              'Reference',
                              'Warehouse',
                              'Expiry date',
                              'Vendor',
                              'Ordered Qty',
                              'Total Qty',
                            ])
                              DataColumn(
                                label: Text(title),
                                numeric: title.endsWith('Qty'),
                              ),
                          ],
                          rows: [
                            for (var i = 0; i < lines.length; i++)
                              _row(lines[i], i),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

  DataRow _row(Map<String, dynamic> line, int index) {
    final reference = '${line['reference'] ?? ''}';
    final warehouse = StoreBranchIdentityRegistry.displayName(
      '${line['warehouse'] ?? ''}',
    );
    return DataRow(
      color: WidgetStatePropertyAll(
        index.isOdd ? const Color(0xFFFAFBFC) : Colors.white,
      ),
      cells: [
        DataCell(
          Text(
            catalogDate(line['mrn_date'] ?? widget.item.data['last_mrn_date']),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(SelectableText('${line['mrn_no'] ?? '—'}')),
        DataCell(
          Tooltip(
            message: reference,
            child: SizedBox(
              width: 170,
              child: SelectableText(
                reference.isEmpty ? '—' : reference,
                maxLines: 2,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
        DataCell(
          Text(
            warehouse.isEmpty ? '—' : warehouse,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        DataCell(Text(catalogDate(line['expiry_date']))),
        DataCell(
          Text(
            formatStockVendor(line['vendor']),
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        DataCell(
          Text(
            catalogQty(line['ordered_qty']),
            style: const TextStyle(color: _muted),
          ),
        ),
        DataCell(
          Container(
            constraints: const BoxConstraints(minWidth: 42),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF5F1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: StockReceiptQuantity(
              quantity: stockNumber(line['total_qty'] ?? line['received_qty']),
              bonus: stockNumber(line['bonus']),
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
