import 'package:daily_order/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/additional_request_group.dart';
import 'inventory_additional_request_tile.dart';

class InventoryAdditionalPanel extends StatefulWidget {
  final List<AdditionalRequestGroup> requests;

  const InventoryAdditionalPanel({super.key, required this.requests});

  @override
  State<InventoryAdditionalPanel> createState() =>
      _InventoryAdditionalPanelState();
}

class _InventoryAdditionalPanelState extends State<InventoryAdditionalPanel> {
  @override
  Widget build(BuildContext context) {
    List<AdditionalRequestGroup> list = [...widget.requests];

    /// SORT FOR INVENTORY
    list.sort((a, b) {
      /// Pending inventory first
      if (a.status == "pending_inventory") return -1;
      if (b.status == "pending_inventory") return 1;

      /// then sent to store
      if (a.status == "sent_to_store") return -1;
      if (b.status == "sent_to_store") return 1;

      /// then done
      if (a.status == "done") return 1;
      if (b.status == "done") return -1;

      return b.createdAt.compareTo(a.createdAt);
    });

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundWidget,
        borderRadius: BorderRadius.circular(14),
      ),

      child: Column(
        children: [
          /// HEADER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Text(
                    "Inventory Additional Requests",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondaryColor,
                    ),
                  ),
                ),

                /// REFRESH BUTTON
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    setState(() {});
                  },
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: const Divider(color: AppColors.primaryColor),
          ),

          /// LIST
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                return InventoryAdditionalRequestTile(request: list[i]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
