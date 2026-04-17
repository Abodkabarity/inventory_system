import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import 'additional_history_dialog.dart';

class BranchAnalyticsDialog extends StatefulWidget {
  final String branch;

  const BranchAnalyticsDialog({super.key, required this.branch});

  @override
  State<BranchAnalyticsDialog> createState() => _BranchAnalyticsDialogState();
}

class _BranchAnalyticsDialogState extends State<BranchAnalyticsDialog> {
  @override
  void initState() {
    super.initState();

    context.read<InventoryBloc>().add(LoadBranchAllChanges(widget.branch));
    context.read<InventoryBloc>().add(LoadBranchAdditionalStats(widget.branch));
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.grey.shade100,
      child: Container(
        width: screen.width * 0.85,
        height: screen.height * 0.9,
        padding: const EdgeInsets.all(24),

        child: BlocBuilder<InventoryBloc, InventoryState>(
          builder: (context, state) {
            final additionalMonth =
                state.additionalMonthBranchCount[widget.branch] ?? 0;

            return Column(
              children: [
                /// HEADER
                Row(
                  children: [
                    Text(
                      widget.branch,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                /// KPI
                Row(
                  children: [
                    _kpiCard(
                      title: "Changes",
                      value: state.allChanges.length,
                      color: Colors.blue,
                      onTap: () {},
                    ),
                    _kpiCard(
                      title: "Additional Month",
                      value: additionalMonth,
                      color: Colors.orange,
                      onTap: () => _openHistory(context),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                /// TITLE
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Branch Activity Timeline",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 10),

                /// LIST
                Expanded(
                  child: state.allChanges.isEmpty
                      ? const Center(child: Text("No activity"))
                      : ListView.builder(
                          itemCount: state.allChanges.length,
                          itemBuilder: (context, i) {
                            final item = state.allChanges[i];

                            return _timelineItem(item);
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// ============================
  /// TIMELINE ITEM (🔥 احترافي)
  /// ============================

  Widget _timelineItem(Map<String, dynamic> item) {
    final source = item['source'] ?? '';
    final time = DateTime.tryParse(item['created_at'] ?? '') ?? DateTime.now();

    IconData icon;
    Color color;
    String title;

    switch (source) {
      case 'order_edit':
        icon = Icons.edit;
        color = Colors.blue;
        title = "Order Edited";
        break;

      case 'mismatch':
        icon = Icons.warning_amber_rounded;
        color = Colors.red;
        title = "Stock Mismatch";
        break;

      case 'max_adj':
        icon = Icons.tune;
        color = Colors.orange;
        title = "Max Adjustment";
        break;

      default:
        icon = Icons.info;
        color = Colors.grey;
        title = "Activity";
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// LINE + ICON
        Column(
          children: [
            Container(width: 3, height: 10, color: Colors.grey.shade300),
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withOpacity(.15),
              child: Icon(icon, size: 18, color: color),
            ),
            Container(width: 3, height: 70, color: Colors.grey.shade300),
          ],
        ),

        const SizedBox(width: 12),

        /// CONTENT
        Expanded(
          child: Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 15),

            child: Padding(
              padding: const EdgeInsets.all(14),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// HEADER
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('hh:mm a').format(time),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  /// ITEM NAME
                  Text(
                    item['item_name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    item['item_code'] ?? '',
                    style: const TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 10),

                  /// VALUES
                  Row(
                    children: [
                      _valueBox("Old", item['old_value'], Colors.red),
                      const SizedBox(width: 10),
                      const Icon(Icons.arrow_forward),
                      const SizedBox(width: 10),
                      _valueBox("New", item['new_value'], Colors.green),
                    ],
                  ),

                  /// REASON
                  if ((item['note'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notes, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item['note'],
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// ============================
  /// VALUE BOX
  /// ============================

  Widget _valueBox(String label, dynamic value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          Text(
            value?.toString() ?? '',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  /// ============================
  /// KPI CARD
  /// ============================

  Widget _kpiCard({
    required String title,
    required int value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ============================
  /// OPEN ADDITIONAL HISTORY
  /// ============================

  void _openHistory(BuildContext context) {
    final bloc = context.read<InventoryBloc>();

    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: InventoryAdditionalHistoryDialog(branch: widget.branch),
      ),
    );
  }
}
