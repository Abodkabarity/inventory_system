import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/datasources/remote/stock_catalog_remote_ds.dart';
import '../../../data/datasources/remote/stock_management_remote_ds.dart';
import '../../../data/datasources/remote/stock_expiry_remote_ds.dart';
import '../../../domain/entities/inventory_page.dart';
import '../../inventory_dashboard/page/stock_catalog_page.dart';
import '../../inventory_dashboard/page/stock_management_page.dart';
import '../../inventory_dashboard/page/stock_expiry_page.dart';
import '../../widgets/retained_page_stack.dart';

/// Full-network read-only stock pages. The parent obtains authorization from
/// can_read_main_zone_stock; the server independently guards every stock read.
class ZoneStockWorkspace extends StatelessWidget {
  const ZoneStockWorkspace({
    super.key,
    required this.authorized,
    required this.selectedPage,
    required this.onSelected,
    this.catalogSource,
    this.mrnSource,
    this.cdSource,
    this.expirySource,
  });
  final bool authorized;
  final InventoryPageType selectedPage;
  final ValueChanged<InventoryPageType> onSelected;
  final StockCatalogDataSource? catalogSource;
  final StockManagementDataSource? mrnSource, cdSource;
  final StockExpiryDataSource? expirySource;

  static const pages = [
    InventoryPageType.stockManagement,
    InventoryPageType.mrnOverview,
    InventoryPageType.mrnCdOverview,
    InventoryPageType.nearExpiry,
  ];

  void _select(InventoryPageType page) {
    if (authorized && pages.contains(page)) {
      onSelected(page);
    }
  }

  Widget _buildPage(InventoryPageType page) => switch (page) {
    InventoryPageType.stockManagement => StockCatalogPage(
      dataSource: catalogSource,
      readOnly: true,
    ),
    InventoryPageType.mrnOverview => StockManagementPage(
      dataSource: mrnSource,
      onOpenExpiry: () => _select(InventoryPageType.nearExpiry),
    ),
    InventoryPageType.mrnCdOverview => StockManagementPage(
      dataSource: cdSource,
      cd: true,
      onOpenExpiry: () => _select(InventoryPageType.nearExpiry),
    ),
    InventoryPageType.nearExpiry => StockExpiryPage(
      dataSource: expirySource ?? StockExpiryRemoteDs(Supabase.instance.client),
      productDataSource: mrnSource,
      readOnly: true,
      embedded: true,
    ),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    if (!authorized || !pages.contains(selectedPage)) {
      return const SizedBox.shrink();
    }
    return RetainedPageStack<InventoryPageType>(
      pages: pages,
      selectedPage: selectedPage,
      pageBuilder: (_, page) => _buildPage(page),
    );
  }
}
