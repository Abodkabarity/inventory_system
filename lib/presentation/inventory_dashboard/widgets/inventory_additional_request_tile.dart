import 'package:daily_order/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/additional_request_group.dart';
import 'inventory_additional_request_dialog.dart';

class InventoryAdditionalRequestTile extends StatelessWidget {
  final AdditionalRequestGroup request;

  const InventoryAdditionalRequestTile({super.key, required this.request});

  String _formatDate(DateTime date) {
    return DateFormat("yyyy-MM-dd  HH:mm").format(date);
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusText;

    switch (request.status) {
      case "done":
        statusColor = Colors.green;
        statusText = "DONE";
        break;

      case "sent_to_store":
        statusColor = Colors.blue;
        statusText = "SENT TO STORE";
        break;

      case "rejected":
        statusColor = Colors.red;
        statusText = "REJECTED";
        break;

      default:
        statusColor = Colors.orange;
        statusText = "PENDING INVENTORY";
    }

    return Card(
      color: AppColors.white,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: ListTile(
        title: Text(
          "${request.branchName} Additional Order",
          style: const TextStyle(
            color: AppColors.secondaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          _formatDate(request.createdAt),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${request.itemsCount} items",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(width: 10),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusText,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ),
        leading: const Icon(
          Icons.add_circle_outline_rounded,
          color: AppColors.secondaryColor,
        ),
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => InventoryAdditionalRequestDialog(
              groupId: request.groupId,
              branch: request.branchName,
            ),
          );
        },
      ),
    );
  }
}
