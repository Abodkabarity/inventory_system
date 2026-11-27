import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/print_service.dart';
import '../../../domain/entities/store_order_item.dart';
import '../../../domain/entities/tibah_order.dart';
import 'tibah_order_toolbar.dart';
import 'store_branch_identity.dart';

class OrdersPanel extends StatelessWidget {
  final List<StoreOrderItem> items;
  final String? branch;
  final bool isSubmitted;
  final bool isLoading;
  final VoidCallback? onClose;
  final TibahOrder? tibahOrder;
  final bool tibahItemsLoaded;
  final VoidCallback? onRefresh;
  final String? loadError;
  const OrdersPanel({
    super.key,
    required this.items,
    required this.branch,
    required this.isSubmitted,
    required this.isLoading,
    this.onClose,
    this.tibahOrder,
    this.tibahItemsLoaded = false,
    this.onRefresh,
    this.loadError,
  });

  @override
  Widget build(BuildContext context) {
    if (branch == null) {
      return const Center(
        child: Text("Select Branch", style: TextStyle(fontSize: 18)),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.backgroundWidget,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Spacer(),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Branch: ',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                    StoreBranchLabel(
                      branchName: branch!,
                      compactBadge: false,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.black, size: 34),
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          if (!isSubmitted)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text(
                "This branch has not submitted the order yet",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          if (tibahOrder != null)
            TibahOrderToolbar(
              key: ValueKey(tibahOrder!.id),
              order: tibahOrder!,
              items: items,
              loaded: tibahItemsLoaded,
              onRefresh: onRefresh ?? () {},
              onClose: onClose,
            ),
          if (TibahOrder.isBranch(branch!) && loadError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                loadError!,
                style: const TextStyle(color: Color(0xFF9F1239)),
              ),
            ),
          if (TibahOrder.isBranch(branch!) && tibahOrder == null && !isLoading)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.black),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh order'),
            ),
          if (isSubmitted &&
              tibahOrder == null &&
              !TibahOrder.isBranch(branch!))
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.print, color: AppColors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  label: const Text(
                    "Print Medicine",
                    style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: items.isEmpty
                      ? null
                      : () {
                          PrintService.printOrders(
                            branch: branch!,
                            items: items,
                            isGeneral: false,
                          );
                        },
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.print, color: AppColors.white),
                  label: const Text(
                    "Print General",
                    style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: items.isEmpty
                      ? null
                      : () {
                          PrintService.printOrders(
                            branch: branch!,
                            items: items,
                            isGeneral: true,
                          );
                        },
                ),
              ],
            ),

          const SizedBox(height: 20),

          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (!isSubmitted) {
      return const Center(
        child: Text(
          "No order submitted",
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryColor),
      );
    }

    if (tibahOrder != null && !tibahOrder!.isReady) {
      return const Center(child: Text('Preparing order quantities...'));
    }

    if (items.isEmpty) {
      return const Center(
        child: Text("No items in this order", style: TextStyle(fontSize: 16)),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];

        return Card(
          color: AppColors.white,
          child: ListTile(
            title: Text(item.itemName, textAlign: TextAlign.center),
            subtitle: Text(item.barcode, textAlign: TextAlign.center),
            trailing: Text(
              item.quantity.toString(),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            leading: Icon(Icons.task, color: AppColors.secondaryColor),
          ),
        );
      },
    );
  }
}
