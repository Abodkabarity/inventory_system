import 'package:flutter/material.dart';

class BranchEffectivenessDialog extends StatelessWidget {
  final String branchName;
  final List<Map<String, dynamic>> products;

  const BranchEffectivenessDialog({
    super.key,
    required this.branchName,
    required this.products,
  });

  Color statusColor(String status) {
    switch (status) {
      case 'sold_within_3d':
        return const Color(0xff10B981);

      case 'sold_after_3d':
        return const Color(0xffF59E0B);

      case 'not_sold':
        return const Color(0xffEF4444);

      default:
        return const Color(0xff94A3B8);
    }
  }

  String statusLabel(String status) {
    switch (status) {
      case 'sold_within_3d':
        return 'Sold Fast';

      case 'sold_after_3d':
        return 'Sold Later';

      case 'not_sold':
        return 'Not Sold';

      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 1200,
        height: 700,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.store, color: Color(0xff10B981)),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      branchName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: DataTable(
                  headingRowColor: const WidgetStatePropertyAll(
                    Color(0xffF1F5F9),
                  ),

                  columns: const [
                    DataColumn(label: Text('Item Code')),

                    DataColumn(label: Text('Item Name')),

                    DataColumn(label: Text('Requested')),

                    DataColumn(label: Text('Sold')),

                    DataColumn(label: Text('Days')),

                    DataColumn(label: Text('First Sale')),

                    DataColumn(label: Text('Status')),
                  ],

                  rows: products.map((p) {
                    final status = p['effectiveness_status']?.toString() ?? '';

                    final color = statusColor(status);

                    return DataRow(
                      cells: [
                        DataCell(Text(p['item_code']?.toString() ?? '')),

                        DataCell(Text(p['item_name']?.toString() ?? '')),

                        DataCell(Text('${p['request_qty']}')),

                        DataCell(
                          Text(
                            '${p['total_sold_qty']}',
                            style: TextStyle(
                              color: (p['total_sold_qty'] ?? 0) > 0
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        DataCell(Text('${p['days_elapsed']}')),

                        DataCell(
                          Text(
                            p['days_to_first_sale'] == null
                                ? '-'
                                : '${p['days_to_first_sale']} d',
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
                              statusLabel(status),
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
