import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/stock_expiry_remote_ds.dart';
import '../../../domain/entities/inventory_page.dart';
import '../widgets/inventory_drawer.dart';
import 'availability_kpi_page.dart';
import 'fill_rate_kpi_page.dart';
import 'stock_catalog_page.dart';
import 'stock_expiry_page.dart';
import 'stock_management_page.dart';

/// A separate shell keeps inventory loaders, subscriptions and write actions
/// out of the view role's session. Only these five pages can be selected.
class ViewDashboardPage extends StatefulWidget {
  final String runDate;
  const ViewDashboardPage({super.key, required this.runDate});

  static const pages = {
    InventoryPageType.stockManagement,
    InventoryPageType.mrnOverview,
    InventoryPageType.nearExpiry,
    InventoryPageType.availabilityKpi,
    InventoryPageType.fillRateKpi,
  };

  @override
  State<ViewDashboardPage> createState() => _ViewDashboardPageState();
}

class _ViewDashboardPageState extends State<ViewDashboardPage> {
  InventoryPageType _page = InventoryPageType.stockManagement;
  bool _collapsed = false;

  void _select(InventoryPageType page) {
    if (!ViewDashboardPage.pages.contains(page)) return;
    setState(() => _page = page);
  }

  Widget _buildPage() => switch (_page) {
    InventoryPageType.stockManagement => const StockCatalogPage(readOnly: true),
    InventoryPageType.mrnOverview => StockManagementPage(
      onOpenExpiry: () => _select(InventoryPageType.nearExpiry),
    ),
    InventoryPageType.nearExpiry => StockExpiryPage(
      dataSource: StockExpiryRemoteDs(Supabase.instance.client),
      embedded: true,
      readOnly: true,
    ),
    InventoryPageType.availabilityKpi => AvailabilityKpiPage(
      runDate: widget.runDate,
    ),
    InventoryPageType.fillRateKpi => const FillRateKpiPage(),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xffF4F7FB),
    body: Stack(
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: _collapsed ? 0 : 270,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: _collapsed ? 0 : 1,
                  child: InventoryDrawer.view(
                    selectedPage: _page,
                    onSelected: _select,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildPage()),
          ],
        ),
        Positioned(
          top: 16,
          left: _collapsed ? 10 : 252,
          child: Tooltip(
            message: _collapsed ? 'Show menu' : 'Hide menu',
            child: Material(
              color: Colors.white,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => setState(() => _collapsed = !_collapsed),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Icon(
                    _collapsed
                        ? Icons.keyboard_double_arrow_right_rounded
                        : Icons.keyboard_double_arrow_left_rounded,
                    color: AppColors.primaryColor,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
