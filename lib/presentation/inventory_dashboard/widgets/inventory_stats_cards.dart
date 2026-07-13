import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class InventoryStatsCards extends StatelessWidget {
  final int totalOrdersToday;
  final int submitted;
  final int additionalToday;
  final int additionalMonth;
  final int pendingInventory;
  final int sentToStore;

  const InventoryStatsCards({
    super.key,
    required this.totalOrdersToday,
    required this.submitted,
    required this.additionalToday,
    required this.additionalMonth,
    required this.pendingInventory,
    required this.sentToStore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _card(
              title: "Total Orders Today",
              value: totalOrdersToday.toString(),
              icon: Icons.store,
              color: Colors.deepPurple,
            ),
          ),

          SizedBox(width: 10.w),

          Expanded(
            flex: 5,
            child: _card(
              title: "Submitted Orders",
              value: submitted.toString(),
              icon: Icons.inventory,
              color: Colors.green,
            ),
          ),

          SizedBox(width: 10.w),

          Expanded(
            flex: 5,
            child: _card(
              title: "Additional Today",
              value: additionalToday.toString(),
              icon: Icons.add_box,
              color: Colors.orange,
            ),
          ),

          SizedBox(width: 10.w),

          Expanded(
            flex: 5,
            child: _card(
              title: "Rejected Additional",
              value: additionalMonth.toString(),
              icon: Icons.cancel_rounded,
              color: Colors.redAccent,
            ),
          ),

          SizedBox(width: 10.w),

          Expanded(
            flex: 6,
            child: _dualCard(
              title: "Pending / Sent To Store",
              leftLabel: "Pending",
              leftValue: pendingInventory.toString(),
              rightLabel: "Sent",
              rightValue: sentToStore.toString(),
              icon: Icons.hourglass_bottom,
              color: Colors.deepOrange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dualCard({
    required String title,
    required String leftLabel,
    required String leftValue,
    required String rightLabel,
    required String rightValue,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      height: 100,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 14),
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
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _miniValue(leftValue, leftLabel, color),
                    Container(
                      width: 1,
                      height: 26,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: const Color(0xFFE2E8F0),
                    ),
                    _miniValue(rightValue, rightLabel, Colors.blueGrey),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniValue(String value, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
      ],
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
      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 18),
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
