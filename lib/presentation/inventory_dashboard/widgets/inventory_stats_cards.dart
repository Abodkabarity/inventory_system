import 'package:flutter/material.dart';

class InventoryStatsCards extends StatelessWidget {
  final int totalOrdersToday;
  final int submitted;
  final int additionalToday;
  final int additionalMonth;
  final int pendingInventory;

  const InventoryStatsCards({
    super.key,
    required this.totalOrdersToday,
    required this.submitted,
    required this.additionalToday,
    required this.additionalMonth,
    required this.pendingInventory,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: _card(
              title: "Total Orders Today",
              value: totalOrdersToday.toString(),
              icon: Icons.store,
              color: Colors.deepPurple,
            ),
          ),

          const SizedBox(width: 20),

          Expanded(
            child: _card(
              title: "Submitted Orders",
              value: submitted.toString(),
              icon: Icons.inventory,
              color: Colors.green,
            ),
          ),

          const SizedBox(width: 20),

          Expanded(
            child: _card(
              title: "Additional Today",
              value: additionalToday.toString(),
              icon: Icons.add_box,
              color: Colors.orange,
            ),
          ),

          const SizedBox(width: 20),

          Expanded(
            child: _card(
              title: "Additional This Month",
              value: additionalMonth.toString(),
              icon: Icons.calendar_month,
              color: Colors.blue,
            ),
          ),

          const SizedBox(width: 20),

          Expanded(
            child: _card(
              title: "Pending Inventory Approval",
              value: pendingInventory.toString(),
              icon: Icons.hourglass_bottom,
              color: Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      height: 100,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            color: Colors.black.withValues(alpha: .05),
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),

          const SizedBox(width: 30),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
