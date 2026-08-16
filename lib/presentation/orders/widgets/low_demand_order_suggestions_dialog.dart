import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';

class LowDemandOrderSuggestion {
  const LowDemandOrderSuggestion({
    required this.itemCode,
    required this.itemName,
    required this.demand,
    required this.branchStock,
    required this.maxQty,
    required this.step,
  });

  final String itemCode;
  final String itemName;
  final num demand;
  final num branchStock;
  final int maxQty;
  final int step;
}

class LowDemandOrderSuggestionsDialog extends StatefulWidget {
  const LowDemandOrderSuggestionsDialog({
    super.key,
    required this.items,
    required this.onAdd,
  });

  final List<LowDemandOrderSuggestion> items;
  final Future<bool> Function(LowDemandOrderSuggestion item, int quantity)
  onAdd;

  static Future<void> show({
    required BuildContext context,
    required List<LowDemandOrderSuggestion> items,
    required Future<bool> Function(LowDemandOrderSuggestion item, int quantity)
    onAdd,
  }) async {
    if (items.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          LowDemandOrderSuggestionsDialog(items: items, onAdd: onAdd),
    );
  }

  @override
  State<LowDemandOrderSuggestionsDialog> createState() =>
      _LowDemandOrderSuggestionsDialogState();
}

class _LowDemandOrderSuggestionsDialogState
    extends State<LowDemandOrderSuggestionsDialog> {
  late final Map<String, int> _quantities;
  final Set<String> _added = <String>{};
  final Set<String> _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _quantities = {for (final item in widget.items) item.itemCode: item.step};
  }

  String _number(num value) {
    final rounded = value.round();
    return value == rounded ? '$rounded' : value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Column(
          children: [
            _buildHeader(),
            _buildGuidance(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                itemCount: widget.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) => _buildItem(widget.items[index]),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.secondaryColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add_shopping_cart_rounded,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Branch Stock Less Than Demand To Review',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.items.length} eligible item(s) may need a small quantity.',
                  style: TextStyle(
                    color: AppColors.white.withValues(alpha: .76),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _saving.isEmpty ? () => Navigator.pop(context) : null,
            icon: const Icon(Icons.close_rounded, color: AppColors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidance() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blueSoft,
        border: Border.all(
          color: AppColors.primaryColor.withValues(alpha: .35),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primaryColor),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Review only the items you need. Click Add to order to include an item. '
              'Leave any unwanted item untouched, then press Next to continue to Review Changes.',
              style: TextStyle(
                color: AppColors.text,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(LowDemandOrderSuggestion item) {
    final quantity = _quantities[item.itemCode] ?? item.step;
    final added = _added.contains(item.itemCode);
    final saving = _saving.contains(item.itemCode);
    final atLimit = quantity + item.step > item.maxQty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: added ? const Color(0xfff0fbf6) : AppColors.bg,
        border: Border.all(
          color: added ? const Color(0xff8de0b5) : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.itemCode,
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _metric('Demand 30D', _number(item.demand)),
          _metric('Branch stock', _number(item.branchStock)),
          const SizedBox(width: 10),
          SizedBox(
            width: 138,
            child: Column(
              children: [
                const Text(
                  'Add quantity',
                  style: TextStyle(color: AppColors.subText, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _stepButton(
                      icon: Icons.remove_rounded,
                      enabled: !added && !saving && quantity > item.step,
                      onTap: () => setState(
                        () => _quantities[item.itemCode] = quantity - item.step,
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '$quantity',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _stepButton(
                      icon: Icons.add_rounded,
                      enabled: !added && !saving && !atLimit,
                      onTap: () => setState(
                        () => _quantities[item.itemCode] = quantity + item.step,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  atLimit ? 'Limit stock' : 'Maximum ${item.maxQty}',
                  style: TextStyle(
                    color: atLimit
                        ? const Color(0xffd97706)
                        : AppColors.subText,
                    fontSize: 10,
                    fontWeight: atLimit ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 155.w,
            child: FilledButton.icon(
              onPressed: added || saving
                  ? null
                  : () => _addItem(item, quantity),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                disabledBackgroundColor: added
                    ? const Color(0xffd8f5e5)
                    : AppColors.border,
                foregroundColor: AppColors.white,
                disabledForegroundColor: added
                    ? const Color(0xff087a47)
                    : AppColors.subText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      added ? Icons.check_rounded : Icons.add_rounded,
                      size: 18,
                    ),
              label: Text(added ? 'Added' : 'Add to order'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return SizedBox(
      width: 98,
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.subText, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: icon == Icons.add_rounded ? 'Increase' : 'Decrease',
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      color: AppColors.secondaryColor,
    );
  }

  Future<void> _addItem(LowDemandOrderSuggestion item, int quantity) async {
    setState(() => _saving.add(item.itemCode));
    final saved = await widget.onAdd(item, quantity);
    if (!mounted) return;
    setState(() {
      _saving.remove(item.itemCode);
      if (saved) _added.add(item.itemCode);
    });
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Text(
            '${_added.length} of ${widget.items.length} item(s) added',
            style: const TextStyle(
              color: AppColors.subText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _saving.isEmpty ? () => Navigator.pop(context) : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.secondaryColor,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Next: Review Changes'),
          ),
        ],
      ),
    );
  }
}
