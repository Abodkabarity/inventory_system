import 'package:flutter/material.dart';

import '../../../domain/entities/inventory_page.dart';
import '../../widgets/retained_page_stack.dart';

/// Keeps Overview after its first visit. Other Inventory pages still close
/// normally when leaving them, including pages with their own access gates.
class InventoryOverviewStack extends StatelessWidget {
  const InventoryOverviewStack({
    super.key,
    required this.selectedPage,
    required this.pageBuilder,
  });

  final InventoryPageType selectedPage;
  final Widget Function(BuildContext, InventoryPageType) pageBuilder;

  @override
  Widget build(BuildContext context) => RetainedPageStack<InventoryPageType>(
    pages: [
      InventoryPageType.stockManagement,
      if (selectedPage != InventoryPageType.stockManagement) selectedPage,
    ],
    selectedPage: selectedPage,
    pageBuilder: pageBuilder,
  );
}
