import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/print_service.dart';
import '../../../domain/entities/store_order_item.dart';

class OrdersPanel extends StatelessWidget {
  final List<StoreOrderItem> items;
  final String? branch;
  final bool isSubmitted;
  final bool isLoading;

  const OrdersPanel({
    super.key,
    required this.items,
    required this.branch,
    required this.isSubmitted,
    required this.isLoading,
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
            padding: const EdgeInsets.all(16),
            child: Text(
              "Branch: $branch",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
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

          if (isSubmitted)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.print, color: AppColors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
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
