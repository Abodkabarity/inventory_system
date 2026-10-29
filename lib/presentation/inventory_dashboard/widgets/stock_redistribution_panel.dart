import 'package:flutter/material.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../domain/entities/stock_redistribution_plan.dart';
import 'stock_catalog_visuals.dart';

class StockRedistributionPanel extends StatelessWidget {
  final StockRedistributionPlan plan;
  const StockRedistributionPanel({super.key, required this.plan});
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<Map<String, String>>(
    valueListenable: StoreBranchIdentityRegistry.groups,
    builder: (context, _, _) => Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: catalogTeal.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: catalogTeal.withValues(alpha: .15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Can we move extra stock to branches that need it?',
            style: TextStyle(
              color: catalogInk,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Based on Daily Order dated ${catalogDate(plan.runDate?.toIso8601String())} • Suggested transfers only',
            style: const TextStyle(color: catalogMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (!plan.fresh)
            const Text(
              'Daily Order and branch stock need to be updated to matching dates before we can suggest how much to move.',
              style: TextStyle(color: catalogMuted, fontSize: 12),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                CatalogPill(
                  'Extra in Daily Order: ${catalogQty(plan.declaredExtra)} Qty',
                  color: catalogBlue,
                ),
                CatalogPill(
                  'Can be taken from branches: ${catalogQty(plan.safeExtra)} Qty',
                  color: catalogTeal,
                ),
                CatalogPill(
                  'Suggested to move: ${catalogQty(plan.suggestedQty)} Qty',
                  color: catalogTeal,
                ),
                CatalogPill(
                  'Still needed after these moves: ${catalogQty(plan.unmetNeed)} Qty',
                  color: catalogOrange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              plan.transfers.isEmpty
                  ? plan.declaredExtra <= 0
                        ? 'Daily Order shows no extra Qty in the matched branches, so we cannot suggest taking stock from another branch. The branches listed below still need ${catalogQty(plan.unmetNeed)} Qty in total after allowing for stock already on the way or planned for them. This is a Qty to review, not a new order.'
                        : 'Daily Order shows extra Qty, but we could not match it to a suitable branch that needs it while leaving enough stock for the sending branch. Open the branch details below to see the reasons.'
                  : 'The branches below can share some of their extra stock. The suggested Qty leaves stock for their own needs. Check the Qty, expiry date and any transfers already arranged before moving it.',
              style: const TextStyle(
                color: catalogInk,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (plan.transfers.isNotEmpty)
              _table(
                [
                  'From branch',
                  'To branch',
                  'Suggested Qty',
                  'Qty left in sending branch after all moves',
                  'Why this move?',
                ],
                [
                  for (final t in plan.transfers)
                    [
                      _branch(t.from.branch),
                      _branch(t.to.branch),
                      catalogQty(t.qty),
                      catalogQty(
                        t.from.stock -
                            plan.transfers
                                .where((m) => m.from.branch == t.from.branch)
                                .fold<double>(0, (s, m) => s + m.qty),
                      ),
                      t.reason,
                    ],
                ],
              ),
            Material(
              color: Colors.transparent,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'See branches: ${plan.donors.length} with checked extra stock · ${plan.receivers.length} needing stock',
                  style: const TextStyle(color: catalogMuted, fontSize: 12),
                ),
                children: [
                  if (plan.donors.isNotEmpty)
                    _table(
                      [
                        'Branch with extra stock',
                        'Stock left Qty',
                        'Daily Order extra',
                        'Qty we could take',
                        'Qty to keep for this branch',
                        'Has this branch sold it?',
                      ],
                      [
                        for (final b in plan.donors)
                          [
                            _branch(b.branch),
                            catalogQty(b.stock),
                            catalogQty(b.declaredExtra),
                            catalogQty(b.safeExtra),
                            catalogQty(b.retained),
                            b.noSales90
                                ? 'No recorded sales in 90 days'
                                : 'Sales or a need for stock was recorded',
                          ],
                      ],
                    ),
                  if (plan.receivers.isNotEmpty)
                    _table(
                      [
                        'Branch needing stock',
                        'Stock left Qty',
                        'Estimated sales Qty per day',
                        'Qty still needed',
                        'Qty on the way or already planned',
                      ],
                      [
                        for (final b in plan.receivers)
                          [
                            _branch(b.branch),
                            catalogQty(b.stock),
                            catalogQty(b.daily),
                            catalogQty(b.need),
                            catalogQty(b.reserved),
                          ],
                      ],
                    ),
                  const Text(
                    'Before taking stock from a branch, we leave enough for its own needs. We check its earlier sales, '
                    'estimated sales for the next 30 days and the Qty it is set to keep in Daily Order. '
                    'For branches needing stock, we allow for deliveries on the way and Qty already planned for them, so we do not suggest the same Qty twice. '
                    'That planned Qty has not been added to the stock left today. Suggested moves stay within the same branch group and use matching order quantities.',
                    style: TextStyle(
                      color: catalogMuted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                  if (plan.excluded > 0)
                    Text(
                      'We did not use ${plan.excluded} branches for transfer suggestions. Their stock numbers, order quantities or repeated records need checking:',
                      style: const TextStyle(
                        color: catalogOrange,
                        fontSize: 11,
                      ),
                    ),
                  for (final entry in plan.exclusions.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${_branch(entry.key)}: ${entry.value}',
                        style: const TextStyle(
                          color: catalogMuted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
  String _branch(String value) =>
      StoreBranchIdentityRegistry.displayName(value);
  Widget _table(List<String> headers, List<List<String>> rows) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 42,
        columnSpacing: 22,
        columns: [
          for (final h in headers)
            DataColumn(
              label: Text(
                h,
                style: const TextStyle(color: catalogMuted, fontSize: 12),
              ),
            ),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (final value in row)
                  DataCell(
                    Text(
                      value,
                      style: const TextStyle(color: catalogInk, fontSize: 12),
                    ),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}
