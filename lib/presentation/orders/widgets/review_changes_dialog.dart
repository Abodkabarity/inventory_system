import 'package:flutter/material.dart';

import '../../../domain/entities/daily_order_row.dart';
import '../bloc/order_bloc/orders_state.dart';

class ReviewChangesDialog extends StatelessWidget {
  final List<DailyOrderRow> rows;
  final Map<String, FinalReorderEdit> edits;

  final ValueChanged<String> onEdit;
  final ValueChanged<String> onReset;
  final VoidCallback onClearAll;

  const ReviewChangesDialog({
    super.key,
    required this.rows,
    required this.edits,
    required this.onEdit,
    required this.onReset,
    required this.onClearAll,
  });

  DailyOrderRow? _rowByItem(String itemCode) {
    try {
      return rows.firstWhere((r) => r.itemCode == itemCode);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = edits.values.toList()
      ..sort((a, b) => a.itemCode.compareTo(b.itemCode));

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 980,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Review Changes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onClearAll,
                    child: const Text('Clear all'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No changes'),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowHeight: 44,
                      dataRowMinHeight: 44,
                      dataRowMaxHeight: 72,
                      columns: const [
                        DataColumn(label: Text('Item')),
                        DataColumn(label: Text('Auto')),
                        DataColumn(label: Text('New')),
                        DataColumn(label: Text('Diff')),
                        DataColumn(label: Text('Reason')),
                        DataColumn(label: Text('')),
                      ],
                      rows: list.map((e) {
                        final r = _rowByItem(e.itemCode);
                        final title = r == null
                            ? e.itemCode
                            : '${r.itemCode}\n${r.itemName}';

                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DataCell(Text(e.oldQty.toString())),
                            DataCell(
                              Text(
                                e.newQty.toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                e.diff == 0
                                    ? '0'
                                    : (e.diff > 0 ? '+${e.diff}' : '${e.diff}'),
                              ),
                            ),
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                child: Text(
                                  e.reason,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => onEdit(e.itemCode),
                                    child: const Text('Edit'),
                                  ),
                                  TextButton(
                                    onPressed: () => onReset(e.itemCode),
                                    child: const Text('Reset'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
