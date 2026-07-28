import 'package:daily_order/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/additional_request_group.dart';
import 'additional_request_dialog.dart';
import 'store_branch_identity.dart';

class AdditionalRequestTile extends StatelessWidget {
  final AdditionalRequestGroup request;

  const AdditionalRequestTile({super.key, required this.request});

  String _formatDate(DateTime date) {
    return DateFormat("yyyy-MM-dd  HH:mm").format(date);
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusText;

    if (request.storeStatus == 'processing') {
      statusColor = AppColors.primaryColor;
      statusText = "PROCESSING";
    } else {
      switch (request.status) {
        case "done":
          statusColor = Colors.green;
          statusText = "DONE";
          break;

        case "rejected":
          statusColor = Colors.red;
          statusText = "REJECTED";
          break;

        default:
          statusColor = Colors.orange;
          statusText = "PENDING";
      }
    }

    final isUrgent =
        request.contactLogistic == 'urgent' && request.status != 'done';
    return Card(
      color: isUrgent ? Colors.red.shade50 : AppColors.white,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: ListTile(
        title: request.sourceTable == 'additional_order_inventory'
            ? Text(
                'Additional Order - From Inventory',
                style: TextStyle(
                  color: AppColors.secondaryColor,
                  fontWeight: FontWeight.bold,
                ),
              )
            : StoreBranchLabel(
                branchName: request.branchName,
                suffix: 'Additional Order',
                compactBadge: false,
                style: TextStyle(
                  color: AppColors.secondaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
        subtitle: Text(
          _formatDate(request.createdAt),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),

        /// 🔴🔥 TRAILING (UPDATED)
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            /// ITEMS COUNT
            Text(
              "${request.itemsCount} items",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 10),

            /// 🔴 URGENT BADGE
            if (isUrgent)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "URGENT",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            /// 🟢 STATUS BADGE
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

        leading: Icon(
          request.sourceTable == 'additional_order_inventory'
              ? Icons.inventory_2_rounded
              : Icons.add_circle_outline_rounded,
          color: request.sourceTable == 'additional_order_inventory'
              ? AppColors.primaryColor
              : AppColors.secondaryColor,
        ),

        onTap: () {
          showDialog(
            context: context,
            builder: (_) => AdditionalRequestDialog(
              groupId: request.groupId,
              branch: request.branchName,
              sourceTable: request.sourceTable,
            ),
          );
        },
      ),
    );
  }
}
