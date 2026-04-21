import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/inventory_page.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';

class InventoryDrawer extends StatelessWidget {
  const InventoryDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        return Container(
          width: 260,
          color: Colors.white,
          child: Column(
            children: [
              const SizedBox(height: 20),

              const Text(
                "Inventory",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              _item(
                context,
                "Dashboard",
                Icons.dashboard,
                InventoryPageType.dashboard,
                state,
              ),

              _item(
                context,
                "Mismatch Report",
                Icons.warning,
                InventoryPageType.mismatch,
                state,
              ),

              _item(
                context,
                "Max Adjustment",
                Icons.trending_up,
                InventoryPageType.maxAdjustment,
                state,
              ),

              _item(
                context,
                "Formulary",
                Icons.list_alt,
                InventoryPageType.formulary,
                state,
              ),

              _item(
                context,
                "Assortment",
                Icons.category,
                InventoryPageType.assortment,
                state,
              ),

              _item(
                context,
                "Daily Order",
                Icons.shopping_cart,
                InventoryPageType.dailyOrder,
                state,
              ),
              _item(
                context,
                "TMA",
                Icons.shopping_cart,
                InventoryPageType.tma,
                state,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _item(
    BuildContext context,
    String title,
    IconData icon,
    InventoryPageType page,
    InventoryState state,
  ) {
    final selected = state.currentPage == page;

    return InkWell(
      onTap: () {
        context.read<InventoryBloc>().add(ChangeInventoryPage(page));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: selected ? AppColors.primaryColor.withOpacity(0.1) : null,
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primaryColor : Colors.grey.shade600,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? AppColors.primaryColor : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
