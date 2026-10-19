import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/stock_item_added_date.dart';
import '../../../domain/entities/stock_catalog.dart';
import '../../../domain/entities/stock_distribution.dart';
import '../../../domain/entities/stock_management.dart';
import 'stock_catalog_visuals.dart';

Future<StockDistributionRules?> showStockDistributionRules(
  BuildContext context,
  StockDistributionRules rules,
) => showDialog<StockDistributionRules>(
  context: context,
  builder: (_) => _DistributionRulesDialog(rules: rules),
);

class _DistributionRulesDialog extends StatefulWidget {
  final StockDistributionRules rules;
  const _DistributionRulesDialog({required this.rules});
  @override
  State<_DistributionRulesDialog> createState() =>
      _DistributionRulesDialogState();
}

class _DistributionRulesDialogState extends State<_DistributionRulesDialog> {
  final form = GlobalKey<FormState>();
  late final age = TextEditingController(text: '${widget.rules.maxAgeDays}');
  late final stock = TextEditingController(
    text: catalogQty(widget.rules.minStoreStock).replaceAll(',', ''),
  );
  late final branches = TextEditingController(
    text: '${widget.rules.maxCoveredBranches}',
  );
  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryColor;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 530),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 14, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.secondaryColor,
                    Color.lerp(AppColors.secondaryColor, primary, .4)!,
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: primary.withValues(alpha: .3)),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: AppColors.primaryColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STOCK MANAGEMENT',
                          style: TextStyle(
                            color: Color(0xFFBBD8E8),
                            fontSize: 10,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Distribution rules',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 21),
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose which new products need wider distribution.',
                        style: TextStyle(color: catalogMuted, height: 1.5),
                      ),
                      const SizedBox(height: 22),
                      _ruleField(
                        controller: age,
                        label: 'Maximum product age (days)',
                        helper: 'Days since Created date',
                        unit: 'days',
                        icon: Icons.calendar_month_rounded,
                        minimum: 1,
                        maximum: 365,
                      ),
                      _ruleField(
                        controller: stock,
                        label: 'Minimum STORE stock',
                        helper: 'Stock available in the STORE warehouse',
                        unit: 'Qty',
                        icon: Icons.warehouse_outlined,
                        minimum: 1,
                        maximum: 1000000000,
                        wholeNumbers: false,
                      ),
                      _ruleField(
                        controller: branches,
                        label: 'Maximum covered branches',
                        helper:
                            'Branches with stock or a final order, counted once',
                        unit: 'branches',
                        icon: Icons.hub_outlined,
                        minimum: 0,
                        maximum: 1000,
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: .065),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: primary.withValues(alpha: .18),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.auto_awesome_outlined,
                              color: primary,
                              size: 20,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Highlight products when',
                                    style: TextStyle(
                                      color: catalogInk,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Age ≤ ${_preview(age)} days · STORE ≥ ${_preview(stock)} Qty · Covered branches ≤ ${_preview(branches)}',
                                    style: const TextStyle(
                                      color: catalogInk,
                                      fontSize: 12,
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Reorder is a request. Final order is planned allocation, not confirmed delivery.',
                        style: TextStyle(
                          color: catalogMuted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FBFD),
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: catalogMuted,
                            side: const BorderSide(color: AppColors.border),
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _apply,
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: const Text(
                            'Apply',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.devices_rounded,
                        size: 13,
                        color: catalogMuted,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Saved on this device',
                        style: TextStyle(color: catalogMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _preview(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim());
    return value != null && value.isFinite && value >= 0
        ? catalogQty(value)
        : '—';
  }

  Widget _ruleField({
    required TextEditingController controller,
    required String label,
    required String helper,
    required String unit,
    required IconData icon,
    required double minimum,
    required double maximum,
    bool wholeNumbers = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      cursorColor: AppColors.primaryColor,
      keyboardType: TextInputType.numberWithOptions(decimal: !wholeNumbers),
      style: const TextStyle(
        color: catalogInk,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: const TextStyle(color: catalogMuted, fontSize: 14),
        floatingLabelStyle: const TextStyle(
          color: AppColors.primaryColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        helperText: helper,
        helperMaxLines: 2,
        helperStyle: const TextStyle(
          color: catalogMuted,
          fontSize: 11,
          height: 1.4,
        ),
        errorMaxLines: 2,
        errorStyle: const TextStyle(fontSize: 11),
        filled: true,
        fillColor: const Color(0xFFF7FBFE),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        prefixIcon: Icon(icon, color: AppColors.primaryColor, size: 23),
        suffixText: unit,
        suffixStyle: const TextStyle(
          color: catalogMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.primaryColor.withValues(alpha: .2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.primaryColor,
            width: 1.5,
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      validator: (text) {
        final number = double.tryParse(text?.trim() ?? '');
        return number == null ||
                !number.isFinite ||
                number < minimum ||
                number > maximum ||
                (wholeNumbers && number != number.roundToDouble())
            ? 'Enter ${minimum.toInt()} to ${maximum.toInt()}${wholeNumbers ? ' (whole numbers)' : ''}'
            : null;
      },
    ),
  );

  void _apply() {
    if (!form.currentState!.validate()) return;
    Navigator.pop(
      context,
      StockDistributionRules(
        maxAgeDays: int.parse(age.text.trim()),
        minStoreStock: double.parse(stock.text.trim()),
        maxCoveredBranches: int.parse(branches.text.trim()),
      ),
    );
  }

  @override
  void dispose() {
    age.dispose();
    stock.dispose();
    branches.dispose();
    super.dispose();
  }
}

class StockDistributionPanel extends StatelessWidget {
  final StockCatalogItem item;
  const StockDistributionPanel({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final status = item.distributionStatus;
    final facts = stockMap(item.data['distribution']);
    return CatalogPanel(
      title: 'New product distribution',
      subtitle: status.needsDistribution
          ? 'STORE stock is available. This product needs wider distribution.'
          : status.known
          ? 'Current stock and planned branch allocation'
          : 'A complete Daily Order run from today or yesterday is needed before making a distribution recommendation.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CatalogPill(
                status.label,
                color: status.needsDistribution ? catalogOrange : catalogTeal,
              ),
              CatalogPill(
                '${status.ageDays ?? '—'} days old',
                color: catalogBlue,
              ),
              if (status.receivedAfterCreation)
                CatalogPill(
                  '${status.daysInStore} days in STORE',
                  color: catalogTeal,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                'First STORE MRN: ${formatStockItemAddedDate(status.firstReceivedDate)}',
                style: const TextStyle(
                  color: catalogInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              Text(
                'Latest STORE MRN: ${formatStockItemAddedDate(status.lastReceivedDate)}',
                style: const TextStyle(color: catalogMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (status.known) ...[
            Text(
              '${catalogQty(item.number('store_stock'))} Qty in STORE (${catalogQty(status.availableStore)} after final orders) · ${status.covered} of ${status.eligible} eligible branches have stock or a final order · ${status.uncovered} still uncovered.',
              style: const TextStyle(
                color: catalogInk,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, size) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final stat in [
                    ('Stocked branches', status.stocked),
                    ('Reorder branches', status.reorder),
                    ('Final order branches', status.finalOrders),
                    ('Branches for distribution', status.eligible),
                  ])
                    Container(
                      width: (size.maxWidth - 10) / 2,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withValues(alpha: .045),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryColor.withValues(alpha: .16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stat.$1,
                            style: const TextStyle(
                              color: catalogMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${stat.$2}',
                            style: const TextStyle(
                              color: catalogInk,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Rules: age ≤${item.distributionRules.maxAgeDays} days · STORE ≥${catalogQty(item.distributionRules.minStoreStock)} · covered branches ≤${item.distributionRules.maxCoveredBranches}.',
            style: const TextStyle(
              color: catalogMuted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Orders: ${facts['run_date'] ?? 'unavailable'} · Stock: ${catalogDate(stockMap(item.data['meta'])['stock_updated_at'])}. Reorder requests do not count as allocation. Final orders are not confirmed delivery. Rebuild data after order changes.',
            style: const TextStyle(
              color: catalogMuted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
