import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/inventory_edit_item.dart';

class InventoryEditsPanel extends StatelessWidget {
  final List<InventoryEditItem> edits;
  final String? branch;
  final bool isSubmitted;
  final bool isLoading;

  const InventoryEditsPanel({
    super.key,
    required this.edits,
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
              "Branch Edits: $branch",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
          ),

          const SizedBox(height: 10),

          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (!isSubmitted) {
      return const Center(
        child: Text(
          "This branch has not submitted the order yet",
          style: TextStyle(color: Colors.redAccent),
        ),
      );
    }

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryColor),
      );
    }

    if (edits.isEmpty) {
      return const Center(child: Text("No edits made by this branch"));
    }

    return ListView.builder(
      itemCount: edits.length,
      itemBuilder: (context, i) {
        final item = edits[i];

        return Card(
          child: ListTile(
            leading: const Icon(Icons.edit),
            title: Text(item.itemName),
            subtitle: Text(item.itemCode),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${item.oldQty} → ${item.newQty}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),

                const SizedBox(width: 10),

                Text(
                  "+${item.diff}",
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
