import 'package:flutter/material.dart';

class ProductEffectivenessDialog extends StatelessWidget {
  final String itemCode;
  final String itemName;
  final List<Map<String, dynamic>> branches;

  const ProductEffectivenessDialog({
    super.key,
    required this.itemCode,
    required this.itemName,
    required this.branches,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'sold_within_3d':
        return const Color(0xff10B981);

      case 'sold_after_3d':
        return const Color(0xffF59E0B);

      case 'pending':
        return const Color(0xff3B82F6);

      case 'not_sold':
        return const Color(0xffEF4444);

      default:
        return const Color(0xff94A3B8);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'sold_within_3d':
        return 'Effective';

      case 'sold_after_3d':
        return 'Slow Sale';

      case 'pending':
        return 'Pending Review';

      case 'not_sold':
        return 'Not Effective';

      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 1100,
        height: 700,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xffF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medication, color: Color(0xff8B5CF6)),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$itemCode - $itemName',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff1E293B),
                          ),
                        ),
                        Text(
                          '${branches.length} branch requests',
                          style: const TextStyle(color: Color(0xff64748B)),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            Expanded(
              child: branches.isEmpty
                  ? const Center(child: Text('No Branch Data'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: DataTable(
                        headingRowColor: const WidgetStatePropertyAll(
                          Color(0xffF1F5F9),
                        ),

                        columns: const [
                          DataColumn(label: Text('Branch')),
                          DataColumn(label: Text('Requested')),
                          DataColumn(label: Text('Sold')),
                          DataColumn(label: Text('Days Elapsed')),
                          DataColumn(label: Text('First Sale')),
                          DataColumn(label: Text('Status')),
                        ],

                        rows: branches.map((b) {
                          final status =
                              b['effectiveness_status']?.toString() ?? '';

                          final color = _statusColor(status);

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(b['branch_name']?.toString() ?? ''),
                              ),

                              DataCell(Text('${b['request_qty'] ?? 0}')),

                              DataCell(
                                Text(
                                  '${b['total_sold_qty'] ?? 0}',
                                  style: TextStyle(
                                    color: (b['total_sold_qty'] ?? 0) > 0
                                        ? const Color(0xff10B981)
                                        : const Color(0xffEF4444),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                              DataCell(Text('${b['days_elapsed'] ?? 0} d')),

                              DataCell(
                                Text(
                                  b['days_to_first_sale'] == null
                                      ? '-'
                                      : '${b['days_to_first_sale']} d',
                                ),
                              ),

                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _statusLabel(status),
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
