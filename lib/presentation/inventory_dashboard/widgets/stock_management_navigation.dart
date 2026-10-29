import 'package:flutter/material.dart';
import '../../../domain/entities/inventory_page.dart';

/// An independent workspace section, with room for later stock review tools.
class StockManagementNavigation extends StatefulWidget {
  final InventoryPageType selectedPage;
  final ValueChanged<InventoryPageType> onSelected;
  const StockManagementNavigation({
    super.key,
    required this.selectedPage,
    required this.onSelected,
  });
  @override
  State<StockManagementNavigation> createState() =>
      _StockManagementNavigationState();
}

class _StockManagementNavigationState extends State<StockManagementNavigation> {
  bool _expanded = true;
  bool get _active =>
      widget.selectedPage == InventoryPageType.stockManagement ||
      widget.selectedPage == InventoryPageType.mrnOverview ||
      widget.selectedPage == InventoryPageType.mrnCdOverview ||
      widget.selectedPage == InventoryPageType.nearExpiry;
  @override
  void didUpdateWidget(covariant StockManagementNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPage != widget.selectedPage && _active) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: _active ? const Color(0xFF80C8C8) : const Color(0xFFE4EAF1),
      ),
      boxShadow: [
        if (_active)
          const BoxShadow(
            color: Color(0x0C008A83),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
      ],
    ),
    child: Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(17),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF142C40), Color(0xFF11646A)],
                ),
                borderRadius: _expanded
                    ? const BorderRadius.vertical(top: Radius.circular(17))
                    : BorderRadius.circular(17),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.warehouse_outlined,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stock Management',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 23,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(9, 10, 9, 10),
                  child: Column(
                    children: [
                      _entry(
                        InventoryPageType.stockManagement,
                        'Overview',
                        'All products & demand insights',
                        Icons.space_dashboard_outlined,
                      ),
                      const SizedBox(height: 5),
                      _entry(
                        InventoryPageType.mrnOverview,
                        'MRN Overview',
                        'Receipts, stock & sales',
                        Icons.receipt_long_outlined,
                      ),
                      const SizedBox(height: 5),
                      _entry(
                        InventoryPageType.mrnCdOverview,
                        'MRN CD Overview',
                        'Branch receipts, stock & sales',
                        Icons.local_shipping_outlined,
                      ),
                      const SizedBox(height: 5),
                      _entry(
                        InventoryPageType.nearExpiry,
                        'Near Expiry',
                        'Expiry checks & notes',
                        Icons.event_available_outlined,
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    ),
  );
  Widget _entry(
    InventoryPageType page,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final selected = widget.selectedPage == page;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelected(page),
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF7F5) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? const Color(0xFFB4DFD9) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 21,
                color: selected
                    ? const Color(0xFF008A83)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF007A74)
                            : const Color(0xFF24374A),
                        fontSize: 16,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF008A83),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
