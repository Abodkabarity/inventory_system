import 'package:flutter/material.dart';

import '../../../core/utils/stock_vendor.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../domain/entities/stock_management.dart';
import 'stock_catalog_visuals.dart';

/// Receipt facts share one layout; bonus is included in the reported total.
class StockMrnReceiptSummary extends StatelessWidget {
  final StockManagementItem item;
  const StockMrnReceiptSummary({super.key, required this.item});

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<Map<String, String>>(
    valueListenable: StoreBranchIdentityRegistry.groups,
    builder: (context, _, _) {
      final fields = <({String id, String title, String value, IconData icon})>[
        if (item.isCdReceipt)
          (
            id: 'warehouse',
            title: 'WAREHOUSE',
            value: StoreBranchIdentityRegistry.displayName(
              item.warehouse,
            ).toUpperCase(),
            icon: Icons.storefront_outlined,
          ),
        (
          id: 'date',
          title: 'LAST MRN',
          value: catalogDate(item.data['last_mrn_date']),
          icon: Icons.event_note_outlined,
        ),
        (
          id: 'vendor',
          title: 'VENDOR',
          value: formatStockVendor(item.data['vendor']),
          icon: Icons.local_shipping_outlined,
        ),
        (
          id: 'expiry',
          title: 'EXPIRY DATE',
          value:
              '${catalogDate(item.data['expiry_date'])}${item.number('expiry_count') > 1 ? ' (+${item.number('expiry_count').toInt() - 1})' : ''}',
          icon: Icons.event_outlined,
        ),
        (
          id: 'ordered',
          title: 'ORDERED QTY',
          value: item.data['ordered_quantity'] == null
              ? '—'
              : catalogQty(item.data['ordered_quantity']),
          icon: Icons.shopping_bag_outlined,
        ),
        (
          id: 'total',
          title: 'TOTAL QTY',
          value: catalogQty(item.receiptTotal),
          icon: Icons.move_to_inbox_outlined,
        ),
      ];
      return Container(
        key: const ValueKey('mrn-receipt-cards'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE1E7EF)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: catalogTeal.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        color: Color(0xFF23786C),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Latest receipt',
                      style: TextStyle(
                        color: catalogInk,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (item.text('last_mrn_no').isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'MRN ${item.text('last_mrn_no')}',
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? fields.length
                    : constraints.maxWidth >= 660
                    ? 3
                    : constraints.maxWidth >= 380
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                final scale = MediaQuery.textScalerOf(context).scale(1);
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final field in fields)
                      SizedBox(
                        width:
                            field.id == 'total' && fields.length % columns == 1
                            ? constraints.maxWidth
                            : width,
                        height: 112 * scale,
                        child: _ReceiptField(
                          key: ValueKey('mrn-summary-${field.id}'),
                          title: field.title,
                          value: field.value.isEmpty ? '—' : field.value,
                          icon: field.icon,
                          color: switch (field.id) {
                            'date' || 'ordered' => catalogBlue,
                            'expiry' => catalogOrange,
                            _ => catalogTeal,
                          },
                          total: field.id == 'total',
                          bonus: field.id == 'total' ? item.receiptBonus : 0,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

class _ReceiptField extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  final bool total;
  final double bonus;
  const _ReceiptField({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.total,
    required this.bonus,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(color.withValues(alpha: .10), Colors.white),
          Colors.white,
        ],
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: catalogMuted,
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 30 * MediaQuery.textScalerOf(context).scale(1),
          width: double.infinity,
          child: Tooltip(
            message: value,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 23,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        if (total && bonus > 0) ...[
          const SizedBox(height: 5),
          Tooltip(
            message: 'Bonus is included in Total Qty.',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Bonus ${catalogQty(bonus)} included',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color.lerp(color, catalogInk, .35),
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
