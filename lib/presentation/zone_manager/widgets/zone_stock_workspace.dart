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
class ZoneStockWorkspace extends StatefulWidget {
  const ZoneStockWorkspace({
    super.key,
    required this.authorized,
    this.catalogSource,
    this.mrnSource,
    this.cdSource,
    this.expirySource,
  });
  final bool authorized;
  final StockCatalogDataSource? catalogSource;
  final StockManagementDataSource? mrnSource, cdSource;
  final StockExpiryDataSource? expirySource;

  static const pages = [
    InventoryPageType.stockManagement,
    InventoryPageType.mrnOverview,
    InventoryPageType.mrnCdOverview,
    InventoryPageType.nearExpiry,
  ];

  @override
  State<ZoneStockWorkspace> createState() => _ZoneStockWorkspaceState();
}

class _ZoneStockWorkspaceState extends State<ZoneStockWorkspace> {
  InventoryPageType _page = InventoryPageType.stockManagement;
  void _select(InventoryPageType page) {
    if (widget.authorized && ZoneStockWorkspace.pages.contains(page)) {
      setState(() => _page = page);
    }
  }

  Widget _buildPage(InventoryPageType page) => switch (page) {
    InventoryPageType.stockManagement => StockCatalogPage(
      dataSource: widget.catalogSource,
      readOnly: true,
    ),
    InventoryPageType.mrnOverview => StockManagementPage(
      dataSource: widget.mrnSource,
      onOpenExpiry: () => _select(InventoryPageType.nearExpiry),
    ),
    InventoryPageType.mrnCdOverview => StockManagementPage(
      dataSource: widget.cdSource,
      cd: true,
      onOpenExpiry: () => _select(InventoryPageType.nearExpiry),
    ),
    InventoryPageType.nearExpiry => StockExpiryPage(
      dataSource:
          widget.expirySource ?? StockExpiryRemoteDs(Supabase.instance.client),
      productDataSource: widget.mrnSource,
      readOnly: true,
      embedded: true,
    ),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    if (!widget.authorized) return const SizedBox.shrink();
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(52, 12, 12, 8),
          color: Colors.white,
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (page, label) in [
                (InventoryPageType.stockManagement, 'Overview'),
                (InventoryPageType.mrnOverview, 'MRN Overview'),
                (InventoryPageType.mrnCdOverview, 'MRN CD Overview'),
                (InventoryPageType.nearExpiry, 'Near Expiry'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _page == page,
                  onSelected: (_) => _select(page),
                ),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'All branches · Read only',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RetainedPageStack<InventoryPageType>(
            pages: ZoneStockWorkspace.pages,
            selectedPage: _page,
            pageBuilder: (_, page) => _buildPage(page),
          ),
        ),
      ],
    );
  }
}
