import 'package:flutter/material.dart';

class ProductBranchDialog extends StatelessWidget {
  final String itemName;
  final List<Map<String, dynamic>> branches;

  const ProductBranchDialog({
    super.key,
    required this.itemName,
    required this.branches,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 900,
        height: 600,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xff0D1117),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medication, color: Color(0xff8B5CF6)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      itemName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
            ),

            // Table
            Expanded(
              child: branches.isEmpty
                  ? const Center(
                      child: Text(
                        'No branch data',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          const Color(0xff1F2937),
                        ),
                        dataRowColor: WidgetStatePropertyAll(
                          const Color(0xff111827),
                        ),
                        dividerThickness: 1,
                        columns: const [
                          DataColumn(
                            label: Text(
                              '#',
                              style: TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Branch',
                              style: TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Requests',
                              style: TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Total Qty',
                              style: TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Approved %',
                              style: TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Rejected %',
                              style: TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        rows: branches.asMap().entries.map((entry) {
                          final i = entry.key;
                          final e = entry.value;
                          final approvedPct = (e['approved_percent'] ?? 0)
                              .toStringAsFixed(1);
                          final rejectedPct = (e['rejected_percent'] ?? 0)
                              .toStringAsFixed(1);

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  '#${i + 1}',
                                  style: const TextStyle(color: Colors.white38),
                                ),
                              ),
                              DataCell(
                                Text(
                                  e['branch_name']?.toString() ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${e['requests']}',
                                  style: const TextStyle(
                                    color: Color(0xff06B6D4),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${e['qty']}',
                                  style: const TextStyle(
                                    color: Color(0xff14B8A6),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                _pctBadge(
                                  '$approvedPct%',
                                  const Color(0xff10B981),
                                ),
                              ),
                              DataCell(
                                _pctBadge(
                                  '$rejectedPct%',
                                  const Color(0xffEF4444),
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

  Widget _pctBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
