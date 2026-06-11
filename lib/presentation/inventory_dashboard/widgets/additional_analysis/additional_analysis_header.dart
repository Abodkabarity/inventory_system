import 'package:flutter/material.dart';

import 'glass_container.dart';

class AdditionalKpiCards extends StatelessWidget {
  final Map<String, dynamic> data;

  const AdditionalKpiCards({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final totalRequests = data['total_requests'] ?? 0;
    final totalQty = data['total_qty'] ?? 0;
    final uniqueProducts = data['unique_products'] ?? 0;
    final uniqueBranches = data['unique_branches'] ?? 0;

    final activeBranchRate = (data['active_branch_rate'] ?? 0) as num;
    final completionRate =
        (data['completion_rate'] ?? 0.0) as num; // status = done only
    final rejectionRate = (data['rejection_rate'] ?? 0.0) as num;
    final avgQty = (data['avg_qty'] ?? 0.0) as num;

    return Column(
      children: [
        // Row 1
        Row(
          children: [
            _card(
              'Total Requests',
              '$totalRequests',
              const Color(0xff06B6D4),
              Icons.list_alt,
            ),
            const SizedBox(width: 16),
            _card(
              'Total Quantity',
              '$totalQty',
              const Color(0xff14B8A6),
              Icons.inventory_2,
            ),
            const SizedBox(width: 16),
            _card(
              'Unique Products',
              '$uniqueProducts',
              const Color(0xff8B5CF6),
              Icons.medication,
            ),
            const SizedBox(width: 16),
            _card(
              'Unique Branches',
              '$uniqueBranches',
              const Color(0xffF59E0B),
              Icons.store,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row 2
        Row(
          children: [
            _card(
              'Branch Request Rate',
              '${activeBranchRate.toStringAsFixed(1)}%',
              const Color(0xff10B981),
              Icons.store_mall_directory_outlined,
            ),
            const SizedBox(width: 16),
            _card(
              'Completion Rate', // ← was Approval Rate
              '${completionRate.toStringAsFixed(1)}%', // ← reads completion_rate (done only)
              const Color(0xff3B82F6),
              Icons.task_alt,
            ),
            const SizedBox(width: 16),
            _card(
              'Rejection Rate',
              '${rejectionRate.toStringAsFixed(1)}%',
              const Color(0xffEF4444),
              Icons.cancel_outlined,
            ),
            const SizedBox(width: 16),
            _card(
              'Avg Quantity',
              avgQty.toStringAsFixed(1),
              const Color(0xffF97316),
              Icons.bar_chart,
            ),
          ],
        ),
      ],
    );
  }

  Widget _card(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: GlassContainer(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
