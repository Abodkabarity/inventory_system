import 'package:flutter/material.dart';

import '../../../core/utils/print_service.dart';
import '../../../domain/entities/store_order_item.dart';

class OrdersPanel extends StatelessWidget {
  final List<StoreOrderItem> items;
  final String? branch;
  final bool isSubmitted;

  const OrdersPanel({
    super.key,
    required this.items,
    required this.branch,
    required this.isSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    if (branch == null) {
      return const Center(
        child: Text("Select Branch", style: TextStyle(fontSize: 18)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            "Branch: $branch",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),

        if (!isSubmitted)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              "This branch has not submitted the order yet",
              style: TextStyle(
                fontSize: 16,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

        if (isSubmitted)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.print),
                label: const Text("Print Medicine"),
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
                icon: const Icon(Icons.print),
                label: const Text("Print General"),
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

        const SizedBox(height: 10),

        Expanded(child: _buildContent()),
      ],
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

    if (items.isEmpty) {
      return const Center(
        child: Text("No items in this order", style: TextStyle(fontSize: 16)),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];

        return ListTile(
          title: Text(item.itemName),
          subtitle: Text(item.barcode ?? ""),
          trailing: Text(item.quantity.toString()),
        );
      },
    );
  }
}
