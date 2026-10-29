import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/stock_management.dart';
import '../../../domain/entities/stock_supply_insight.dart';
import 'stock_catalog_visuals.dart';

Color supplyInsightColor(StockSupplyInsight insight) =>
    insight.hasSupplyAnalysis
    ? switch (insight.effectiveSupply['status']) {
        'limited_supply' => catalogRose,
        'supply_restored' => catalogTeal,
        _ => catalogBlue,
      }
    : switch (insight.status) {
        'back_in_store' => catalogTeal,
        'store_empty' => catalogRose,
        'receipt_pending' => catalogOrange,
        'in_store' => catalogBlue,
        _ => catalogMuted,
      };

class StockSupplyReviewCell extends StatelessWidget {
  final StockManagementItem item;
  const StockSupplyReviewCell({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final insight = StockSupplyInsight.of(item);
    return Tooltip(
      message: insight.usable
          ? '${insight.basis} STORE system-stock history through ${catalogDate(insight.data['through'])}. ${insight.basisDescription} Open the product for evidence and monthly sales.'
          : 'Stock history needs verification. Missing history does not mean the product was unavailable.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CatalogPill(insight.label, color: supplyInsightColor(insight)),
          if (insight.displayGapLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              insight.hasSupplyAnalysis
                  ? insight.supplyDuration(
                      insight.latestSupplyPeriod,
                      compact: true,
                    )
                  : insight.displayGapLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: catalogMuted, fontSize: 11),
            ),
          ],
          if (insight.inferred || insight.hasSupplyAnalysis)
            const Text(
              'Estimated',
              style: TextStyle(color: catalogMuted, fontSize: 10),
            ),
        ],
      ),
    );
  }
}

class StockSupplyInsightPanel extends StatelessWidget {
  final StockManagementItem item;
  const StockSupplyInsightPanel({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final insight = StockSupplyInsight.of(item);
    if (!insight.present) return const SizedBox.shrink();
    final last = insight.hasSupplyAnalysis
        ? insight.latestSupplyPeriod
        : insight.returns.isEmpty || insight.status == 'store_empty'
        ? const <String, dynamic>{}
        : insight.returns.last;
    final gap = insight.displayGapLabel.isNotEmpty
        ? insight.displayGapLabel
        : last['days'] == null
        ? '—'
        : '${last['at_least'] == true ? 'At least ' : ''}${last['days']} days';
    return CatalogPanel(
      title: 'STORE availability & sales',
      subtitle:
          'Daily system stock • History through ${catalogDate(insight.data['through'])}${insight.data['sales_through'] == null ? '' : ' • Sales through ${catalogDate(insight.data['sales_through'])}'}',
      trailing: CatalogPill(insight.label, color: supplyInsightColor(insight)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!insight.usable) ...[
            Text(
              insight.status == 'receipt_pending'
                  ? 'Stock has arrived after the history cutoff. The movement record needs to confirm the return date.'
                  : insight.status == 'pending'
                  ? 'Stock history is not available for this product yet.'
                  : 'A confirmed gap cannot be shown until this history is checked.',
              style: const TextStyle(color: catalogInk, fontSize: 13),
            ),
            for (final reason in insight.reasons)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '• $reason',
                  style: const TextStyle(color: catalogMuted, fontSize: 12),
                ),
              ),
          ] else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 750 ? 2 : 4;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final metric in [
                      (
                        insight.hasSupplyAnalysis
                            ? 'SUPPLY INTERRUPTION'
                            : 'LAST STORE GAP',
                        gap,
                        insight.hasSupplyAnalysis
                            ? 'Small arrivals did not restore enough cover'
                            : 'Full days without recorded stock',
                        catalogRose,
                        Icons.hourglass_empty,
                      ),
                      (
                        insight.hasSupplyAnalysis
                            ? 'MEANINGFUL RETURN'
                            : 'RETURN DATE',
                        catalogDate(
                          insight.hasSupplyAnalysis
                              ? last['returned_at']
                              : insight.data['returned_at'] ??
                                    last['returned_at'],
                        ),
                        insight.hasSupplyAnalysis
                            ? 'Incoming Qty and learned demand cover'
                            : insight.inferred
                            ? 'MRN and reconciled STORE stock'
                            : 'Confirmed by MRN and movements',
                        catalogBlue,
                        Icons.event_available_outlined,
                      ),
                      (
                        'RECEIVED QTY',
                        last['received_qty'] == null
                            ? '—'
                            : catalogQty(last['received_qty']),
                        'Received on the linked return date',
                        catalogTeal,
                        Icons.move_to_inbox_outlined,
                      ),
                      (
                        'STORE STOCK',
                        catalogQty(insight.data['current_qty']),
                        'Ledger ${catalogDate(insight.data['stock_day'])}',
                        catalogTeal,
                        Icons.inventory_2_outlined,
                      ),
                    ])
                      SizedBox(
                        width: width,
                        child: CatalogMetric(
                          title: metric.$1,
                          value: metric.$2,
                          caption: metric.$3,
                          color: metric.$4,
                          icon: metric.$5,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (insight.hasSupplyAnalysis) ...[
              Text(
                'Learned demand ${catalogQty(insight.demandModel['daily_qty'])} Qty/day'
                ' • Meaningful recovery ≥ ${catalogQty(insight.demandModel['recovery_qty'])} Qty'
                ' (${insight.demandModel['recovery_cover_days']} days of cover)'
                '${last.isEmpty ? '' : ' • ${last['small_arrivals']} small arrivals / ${catalogQty(last['small_arrival_qty'])} Qty during this period'}',
                style: const TextStyle(
                  color: catalogInk,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Estimated from ${insight.demandModel['months']} historical months'
                ' • Checked against ${insight.demandModel['holdout_months']} later months'
                ' • Average monthly estimate error ${catalogQty(insight.demandModel['holdout_mae_qty'])} Qty.',
                style: const TextStyle(
                  color: catalogMuted,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (insight.inferred) ...[
              Text(
                'Estimated • ${insight.basisDescription}',
                style: const TextStyle(color: catalogOrange, fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            const Text(
              'STORE stock and branch availability are different. Sales below include all source branches; an empty STORE alone does not prove lost sales.',
              style: TextStyle(color: catalogMuted, fontSize: 12),
            ),
            if (insight.months.isNotEmpty)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: Material(
                  color: Colors.transparent,
                  child: ExpansionTile(
                    key: const ValueKey('supply-monthly-comparison'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Monthly sales and STORE days',
                      style: TextStyle(
                        color: catalogInk,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: DataTable(
                                  headingRowColor: WidgetStatePropertyAll(
                                    catalogBlue.withValues(alpha: .06),
                                  ),
                                  headingTextStyle: const TextStyle(
                                    color: catalogMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  dataTextStyle: const TextStyle(
                                    color: catalogInk,
                                    fontSize: 12,
                                  ),
                                  columnSpacing: 24,
                                  horizontalMargin: 12,
                                  headingRowHeight: 42,
                                  dataRowMinHeight: 36,
                                  dataRowMaxHeight: 42,
                                  columns: [
                                    for (final label in [
                                      'Month',
                                      'Sales Qty',
                                      'Prior-year Qty',
                                      'STORE stocked days',
                                      'STORE empty days',
                                      'Partial days',
                                      if (insight.hasSupplyAnalysis)
                                        'Supply interruption days',
                                    ])
                                      DataColumn(
                                        label: Text(label),
                                        numeric: label != 'Month',
                                      ),
                                  ],
                                  rows: [
                                    for (final month in insight.months)
                                      DataRow(
                                        cells: [
                                          DataCell(
                                            Text(_month(month['month'])),
                                          ),
                                          DataCell(
                                            Text(_qty(month['sales_qty'])),
                                          ),
                                          DataCell(
                                            Text(
                                              _qty(
                                                month['prior_year_sales_qty'],
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              _qty(month['available_days']),
                                              style: const TextStyle(
                                                color: catalogTeal,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              _qty(month['empty_days']),
                                              style: const TextStyle(
                                                color: catalogRose,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              _qty(month['partial_days']),
                                              style: const TextStyle(
                                                color: catalogOrange,
                                              ),
                                            ),
                                          ),
                                          if (insight.hasSupplyAnalysis)
                                            DataCell(
                                              Text(
                                                _qty(month['limited_days']),
                                                style: const TextStyle(
                                                  color: catalogRose,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Partial days include receipts, depletion or adjustments. The opening day is excluded. Current-month sales may cover a later date than movement history.',
                          style: TextStyle(color: catalogMuted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _qty(Object? value) => value == null ? '—' : catalogQty(value);
  String _month(Object? value) {
    final parts = '$value'.split('/');
    final month = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final year = parts.length == 2 ? int.tryParse(parts[1]) : null;
    return month == null || year == null
        ? '$value'
        : DateFormat('MMM yyyy').format(DateTime(year, month));
  }
}
