import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/sales_report_remote_ds.dart';
import '../../../domain/entities/inventory_page.dart';
import '../../../domain/repositories/items_tracker_repository.dart';
import '../../inventory_dashboard/page/sales_report_page.dart';
import '../../inventory_dashboard/widgets/inventory_drawer.dart';
import '../../items_tracker/page/items_tracker_page.dart';
import '../../widgets/retained_page_stack.dart';

class CategoryDashboardPage extends StatefulWidget {
  const CategoryDashboardPage({
    super.key,
    this.itemsRepository,
    this.salesReportDataSource,
  });

  final ItemsTrackerRepository? itemsRepository;
  final SalesReportRemoteDs? salesReportDataSource;

  static const pages = [
    InventoryPageType.itemsTracker,
    InventoryPageType.salesReport,
  ];

  @override
  State<CategoryDashboardPage> createState() => _CategoryDashboardPageState();
}

class _CategoryDashboardPageState extends State<CategoryDashboardPage> {
  InventoryPageType _page = InventoryPageType.itemsTracker;
  bool _collapsed = false;

  void _select(InventoryPageType page) {
    if (!CategoryDashboardPage.pages.contains(page)) return;
    setState(() => _page = page);
  }

  Widget _buildPage(InventoryPageType page) => switch (page) {
    InventoryPageType.itemsTracker => ItemsTrackerPage(
      role: 'category',
      embedded: true,
      repository: widget.itemsRepository,
    ),
    InventoryPageType.salesReport => SalesReportPage(
      dataSource: widget.salesReportDataSource,
    ),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return Scaffold(
        backgroundColor: const Color(0xffF4F7FB),
        drawer: wide
            ? null
            : Drawer(
                width: 290,
                child: InventoryDrawer.category(
                  selectedPage: _page,
                  onSelected: (page) {
                    Navigator.of(context).pop();
                    _select(page);
                  },
                ),
              ),
        body: Stack(
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  width: wide && !_collapsed ? 270 : 0,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 270,
                      maxWidth: 270,
                      child: wide
                          ? InventoryDrawer.category(
                              selectedPage: _page,
                              onSelected: _select,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                Expanded(
                  child: RetainedPageStack<InventoryPageType>(
                    pages: CategoryDashboardPage.pages,
                    selectedPage: _page,
                    pageBuilder: (_, page) => _buildPage(page),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 16,
              left: wide && !_collapsed ? 252 : 10,
              child: Builder(
                builder: (context) => Tooltip(
                  message: wide && !_collapsed ? 'Hide menu' : 'Show menu',
                  child: Material(
                    color: Colors.white,
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: const ValueKey('categoryMenuToggle'),
                      onTap: () {
                        if (wide) {
                          setState(() => _collapsed = !_collapsed);
                        } else {
                          Scaffold.of(context).openDrawer();
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Icon(
                          !wide
                              ? Icons.menu_rounded
                              : _collapsed
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
            ),
          ],
        ),
      );
    },
  );
}
