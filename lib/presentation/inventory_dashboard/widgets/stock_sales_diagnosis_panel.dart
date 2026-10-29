import 'package:flutter/material.dart';

import '../../../core/utils/stock_excel_export.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../core/utils/stock_redistribution_export.dart';
import '../../../domain/entities/stock_sales_diagnosis.dart';
import '../../../domain/entities/stock_daily_sales.dart';
import '../../../domain/entities/stock_redistribution_plan.dart';
import 'stock_redistribution_panel.dart';
import 'stock_catalog_visuals.dart';

class StockSalesDiagnosisPanel extends StatefulWidget {
  final Future<StockSalesDiagnosis> Function(bool refresh) load;
  final String code;
  final Widget? history;
  final StockDailySalesMix? salesMix;
  const StockSalesDiagnosisPanel({
    super.key,
    required this.load,
    required this.code,
    this.history,
    this.salesMix,
  });
  @override
  State<StockSalesDiagnosisPanel> createState() =>
      _StockSalesDiagnosisPanelState();
}

class _StockSalesDiagnosisPanelState extends State<StockSalesDiagnosisPanel> {
  Future<StockSalesDiagnosis>? _future;

  @override
  void didUpdateWidget(covariant StockSalesDiagnosisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) _future = null;
  }

  Color _color(StockSalesDiagnosis d) => switch (d.status) {
    'healthy' || 'distributed' => catalogTeal,
    'availability_decline' ||
    'limited_supply' ||
    'branch_shortage' => catalogRose,
    _ => catalogOrange,
  };

  Future<void> _export(StockSalesDiagnosis d) async {
    try {
      if (d.branches.any(
        (b) => !StoreBranchIdentityRegistry.groups.value.containsKey(
          b.branch.trim().toUpperCase(),
        ),
      )) {
        throw StateError('Branch labels are still loading. Retry shortly.');
      }
      await saveStockExcel([
        {'Item code': widget.code, ...d.exportFields},
        ...stockRedistributionExportRows(
          StockRedistributionPlan.fromDiagnosis(d),
        ),
        ...d.channelChanges(widget.salesMix),
        for (final b in d.branches.where((b) => b.expected > 0))
          {
            'branch': StoreBranchIdentityRegistry.displayName(b.branch),
            'Stock left Qty': b.stockKnown ? b.stock : null,
            'Expected sales Qty in 3 days': b.expected,
            'Sold Qty in 3 days': b.actual,
            'Stock records agree': b.audited ? 'Yes' : 'No',
            'How sales were estimated': switch (b.method) {
              'weekday' => 'Sales on the same weekdays',
              'recent14' => 'Recent daily sales',
              _ => 'Average daily sales',
            },
            'Sales days used': b.trainingDays,
            'Days used to check the estimate': b.validationDays,
            'Average difference from actual daily sales Qty': b.error,
          },
      ], 'sales_analysis_${widget.code}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE6EBF4)),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: ValueKey('sales-analysis-${widget.code}'),
      initiallyExpanded: false,
      maintainState: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text(
        'Sales & stock check',
        style: TextStyle(
          color: catalogInk,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: const Text(
        'Click to show or hide the analysis',
        style: TextStyle(color: catalogMuted, fontSize: 12),
      ),
      onExpansionChanged: (expanded) {
        if (expanded && _future == null) {
          setState(() {
            _future = widget.load(false);
          });
        }
      },
      children: [if (_future != null) _analysis(context)],
    ),
  );

  Widget _analysis(BuildContext context) => FutureBuilder<StockSalesDiagnosis>(
    future: _future,
    builder: (context, snapshot) {
      final d = snapshot.data;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (d != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sales and stock through ${catalogDate(d.evidence['through'])} • STORE and active branches',
                      style: const TextStyle(color: catalogMuted, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (MediaQuery.sizeOf(context).width * .4).clamp(
                        120,
                        260,
                      ),
                    ),
                    child: CatalogPill(d.label, color: _color(d)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            d == null
                ? Row(
                    children: [
                      if (!snapshot.hasError) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          snapshot.hasError
                              ? 'We could not load this check. You can still view the product charts.'
                              : 'Comparing earlier sales with the stock left in each branch…',
                          style: const TextStyle(
                            color: catalogMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (snapshot.hasError)
                        TextButton(
                          onPressed: () => setState(() {
                            _future = widget.load(true);
                          }),
                          child: const Text('Retry'),
                        ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        d.explanation,
                        style: const TextStyle(
                          color: catalogInk,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth < 750 ? 2 : 4;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final m in [
                                (
                                  'LAST 3 DAYS SALES',
                                  '${catalogQty(d.actual)} Qty sold',
                                  'Expected about ${_approx(d.expected)} Qty over the same 3 days.',
                                  Icons.query_stats,
                                  catalogBlue,
                                ),
                                (
                                  'STOCK LEFT FOR',
                                  _stockTime(d.networkCover),
                                  'Stock in STORE + branches together.',
                                  Icons.inventory_2_outlined,
                                  catalogTeal,
                                ),
                                (
                                  'LOW STOCK BRANCHES',
                                  '${_approx(d.shortShare * 100)}%',
                                  'Sales share of branches with low stock.',
                                  Icons.store_outlined,
                                  catalogOrange,
                                ),
                                (
                                  'LAST RECEIVED QTY',
                                  d.latestMrn['qty'] == null
                                      ? '—'
                                      : '${catalogQty(d.latestMrn['qty'])} Qty',
                                  '${catalogDate(d.latestMrn['day'])} • MRN to STORE.',
                                  Icons.move_to_inbox_outlined,
                                  catalogTeal,
                                ),
                              ])
                                SizedBox(
                                  width:
                                      (constraints.maxWidth -
                                          (columns - 1) * 12) /
                                      columns,
                                  child: CatalogMetric(
                                    title: m.$1,
                                    value: m.$2,
                                    caption: m.$3,
                                    icon: m.$4,
                                    color: m.$5,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'There are ${catalogQty(d.physicalStock)} Qty left in STORE and the branches together. '
                        '${d.networkCover == null ? 'We need more sales history to estimate how long this stock could last.' : 'At about ${_approx(d.dailyDemand)} Qty of estimated sales per day, this stock may last ${d.networkCover! < 1 ? 'less than 1 day' : 'about ${_approx(d.networkCover!)} days'}.'}',
                        style: const TextStyle(
                          color: catalogMuted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The branches with less than 3 days of stock normally account for about ${_approx(d.shortShare * 100)}% of estimated sales. '
                        'This helps us focus on the selling branches that need stock most.',
                        style: const TextStyle(
                          color: catalogMuted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Last delivery: ${d.receiptAssessment}. The received Qty shows what arrived on that date. Stock left today is shown separately.',
                        style: const TextStyle(
                          color: catalogMuted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (d.receiptAfterCutoff) ...[
                        const Text(
                          'A new delivery arrived after the stock and sales dates used above. '
                          'Update stock to see how much is now in STORE and the branches.',
                          style: TextStyle(
                            color: catalogOrange,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (d.receiptAwaitingMovements) ...[
                        const Text(
                          'The latest delivery is not fully shown in the stock movements yet. '
                          'Check the stock update before treating it as available.',
                          style: TextStyle(
                            color: catalogOrange,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        'What to do: ${d.action}',
                        style: const TextStyle(
                          color: catalogInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      StockRedistributionPanel(
                        plan: StockRedistributionPlan.fromDiagnosis(d),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.transparent,
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text(
                            'What did we check?',
                            style: TextStyle(fontSize: 13, color: catalogMuted),
                          ),
                          children: [
                            Text(
                              'We look at earlier daily sales in each branch and estimate what it might sell next. '
                              'Where possible, we use days when the product was in stock, so days without stock do not make customer need look smaller. '
                              'We test the estimate against later sales before comparing it with the last 3 days.\n\n'
                              'For about ${catalogQty(d.auditedShare * 100)}% of expected sales, enough stock records were available and agreed with the stock balance. '
                              'For the rest, we use recorded sales as a rough guide. If a product is missing from a current branch stock report, we assume its Qty is zero. '
                              'The result is our best explanation from the available records; it does not prove the cause.',
                              style: const TextStyle(
                                color: catalogMuted,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _channels(d),
                            _branches(d),
                            if (widget.history != null) widget.history!,
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _future = widget.load(true);
                              }),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Check again'),
                            ),
                            TextButton.icon(
                              onPressed: () => _export(d),
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 16,
                              ),
                              label: const Text('Save to Excel'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      );
    },
  );

  Widget _channels(StockSalesDiagnosis d) {
    final rows = d.channelChanges(widget.salesMix);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Type of sale')),
            DataColumn(label: Text('Earlier average Qty per day')),
            DataColumn(label: Text('Average Qty per day in last 3 days')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                cells: [
                  DataCell(Text('${r['channel']}')),
                  DataCell(Text(catalogQty(r['previous_daily_qty']))),
                  DataCell(Text(catalogQty(r['last_3_daily_qty']))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _branches(StockSalesDiagnosis d) =>
      ValueListenableBuilder<Map<String, String>>(
        valueListenable: StoreBranchIdentityRegistry.groups,
        builder: (context, groups, _) {
          final rows = d.branches.where((b) => b.expected > 0).toList()
            ..sort((a, b) => b.expected.compareTo(a.expected));
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 42,
              columns: [
                for (final title in [
                  'Branch',
                  'Stock left Qty',
                  'Expected sales Qty in 3 days',
                  'Sold Qty in 3 days',
                  'How we estimated sales',
                ])
                  DataColumn(label: Text(title)),
              ],
              rows: [
                for (final b in rows.take(12))
                  DataRow(
                    cells: [
                      DataCell(
                        Text(StoreBranchIdentityRegistry.displayName(b.branch)),
                      ),
                      DataCell(
                        Text(b.stockKnown ? catalogQty(b.stock) : 'Unknown'),
                      ),
                      DataCell(Text(catalogQty(b.expected))),
                      DataCell(Text(catalogQty(b.actual))),
                      DataCell(
                        Text(
                          b.availabilityTrained
                              ? 'Used days with stock available'
                              : 'Used earlier recorded sales',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      );

  String _stockTime(double? days) => days == null
      ? 'Cannot estimate yet'
      : days <= 0
      ? 'No stock left'
      : days < 1
      ? 'Less than 1 day'
      : 'About ${_approx(days)} days';
  String _approx(double value) => catalogQty((value * 10).round() / 10);
}
