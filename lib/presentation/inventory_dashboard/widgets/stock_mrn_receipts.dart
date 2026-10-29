import 'package:flutter/material.dart';

import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../core/utils/stock_vendor.dart';
import '../../../domain/entities/stock_management.dart';
import 'stock_catalog_visuals.dart';

/// Receipt numbers and expiry dates remain distinct beneath the daily total.
class StockMrnReceipts extends StatelessWidget {
  final StockManagementItem item;
  const StockMrnReceipts({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final lines = item.list('receipt_lines');
    if (lines.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('mrn-receipt-lines'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.receipt_long_outlined, color: catalogTeal),
        title: Text(
          'MRN receipts (${item.number('receipt_count').toInt()})',
          style: const TextStyle(
            color: catalogInk,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${catalogDate(item.text('last_mrn_date'))} · Total received ${catalogQty(item.data['received_quantity'])} Qty',
          style: const TextStyle(color: catalogMuted, fontSize: 12),
        ),
        children: [
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: StoreBranchIdentityRegistry.groups,
            builder: (context, _, _) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  catalogBlue.withValues(alpha: .06),
                ),
                headingTextStyle: const TextStyle(
                  color: catalogMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                dataTextStyle: const TextStyle(color: catalogInk, fontSize: 13),
                headingRowHeight: 40,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 72,
                columnSpacing: 24,
                horizontalMargin: 12,
                border: TableBorder.all(
                  color: catalogBlue.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10),
                ),
                columns: [
                  for (final title in [
                    'MRN number',
                    'Reference',
                    'Warehouse',
                    'Expiry date',
                    'Vendor',
                    'Ordered Qty',
                    'Received Qty',
                  ])
                    DataColumn(
                      label: Text(title),
                      numeric: title.endsWith('Qty'),
                    ),
                ],
                rows: [
                  for (final line in lines)
                    DataRow(
                      cells: [
                        DataCell(SelectableText('${line['mrn_no'] ?? '—'}')),
                        DataCell(
                          SizedBox(
                            width: 220,
                            child: SelectableText(
                              '${line['reference'] ?? ''}'.isEmpty
                                  ? '—'
                                  : '${line['reference']}',
                              maxLines: 3,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            StoreBranchIdentityRegistry.displayName(
                              '${line['warehouse'] ?? ''}',
                            ),
                          ),
                        ),
                        DataCell(Text(catalogDate(line['expiry_date']))),
                        DataCell(Text(formatStockVendor(line['vendor']))),
                        DataCell(Text(catalogQty(line['ordered_qty']))),
                        DataCell(
                          Text(
                            catalogQty(line['received_qty']),
                            style: const TextStyle(
                              color: catalogTeal,
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
        ],
      ),
    );
  }
}
