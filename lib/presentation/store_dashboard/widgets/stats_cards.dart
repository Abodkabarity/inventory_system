import 'package:flutter/material.dart';

class StatsCards extends StatelessWidget {
  final int totalOrdersToday;
  final int submitted;
  final int additional;
  final int additionalPending;
  final int additionalDone;

  const StatsCards({
    super.key,
    required this.totalOrdersToday,
    required this.submitted,
    required this.additional,
    required this.additionalPending,
    required this.additionalDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          /// TOTAL ORDERS TODAY
          Expanded(
            child: _card(
              title: "Total Orders Today",
              value: totalOrdersToday.toString(),
              icon: Icons.store_mall_directory_outlined,
              color: Colors.deepPurple,
            ),
          ),

          const SizedBox(width: 20),

          /// SUBMITTED ORDERS
          Expanded(
            child: _card(
              title: "Submitted Orders",
              value: submitted.toString(),
              icon: Icons.inventory_2_outlined,
              color: Colors.green,
            ),
          ),

          const SizedBox(width: 20),

          /// ADDITIONAL REQUESTS
          Expanded(
            child: _card(
              title: "Additional Requests",
              value: additional.toString(),
              icon: Icons.add_box_outlined,
              color: Colors.orange,
            ),
          ),

          const SizedBox(width: 20),

          /// PENDING ADDITIONAL
          Expanded(
            child: _card(
              title: "Pending Additional",
              value: additionalPending.toString(),
              icon: Icons.hourglass_bottom,
              color: Colors.redAccent,
            ),
          ),

          const SizedBox(width: 20),

          /// COMPLETED ADDITIONAL
          Expanded(
            child: _card(
              title: "Completed Additional",
              value: additionalDone.toString(),
              icon: Icons.check_circle_outline,
              color: Colors.blue,
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
      height: 130,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            color: Colors.black.withOpacity(.05),
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),

          const SizedBox(width: 16),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
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
