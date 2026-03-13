import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_state.dart';
import 'additional_history_dialog.dart';

class BranchAnalyticsDialog extends StatelessWidget {
  final String branch;

  const BranchAnalyticsDialog({super.key, required this.branch});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey.shade100,
      child: Container(
        width: 900,
        height: 600,
        padding: const EdgeInsets.all(20),

        child: BlocBuilder<InventoryBloc, InventoryState>(
          builder: (context, state) {
            final additionalToday =
                state.additionalTodayBranchCount[branch] ?? 0;

            final additionalMonth = state.additionalMonthCount;

            final editsToday = state.editsCount[branch] ?? 0;

            final editsMonth = state.edits.length;

            return Column(
              children: [
                /// HEADER
                Row(
                  children: [
                    Text(
                      branch,
                      style: const TextStyle(
                        fontSize: 22,
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

                /// KPI CARDS
                Row(
                  children: [
                    _kpiCard(
                      title: "Additional Today",
                      value: additionalToday,
                      color: Colors.orange,
                      onTap: () {
                        _openHistory(context);
                      },
                    ),

                    _kpiCard(
                      title: "Additional Month",
                      value: additionalMonth,
                      color: Colors.deepOrange,
                      onTap: () {
                        _openHistory(context);
                      },
                    ),

                    _kpiCard(
                      title: "Edited Today",
                      value: editsToday,
                      color: Colors.blue,
                      onTap: () {},
                    ),

                    _kpiCard(
                      title: "Edited Month",
                      value: editsMonth,
                      color: Colors.green,
                      onTap: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 25),

                /// EDITED PRODUCTS TODAY
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Edited Products Today",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),

                const SizedBox(height: 10),

                Expanded(
                  child: ListView.builder(
                    itemCount: state.edits.length,
                    itemBuilder: (context, i) {
                      final item = state.edits[i];

                      return Card(
                        elevation: 3,
                        child: ListTile(
                          leading: const Icon(
                            Icons.edit,
                            color: AppColors.primaryColor,
                          ),

                          title: Text(item.itemName),

                          subtitle: Text(item.itemCode),

                          trailing: Text(
                            "${item.oldQty} → ${item.newQty}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      );
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
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.all(16),

          decoration: BoxDecoration(
            color: color.withOpacity(.1),
            borderRadius: BorderRadius.circular(12),
          ),

          child: Column(
            children: [
              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),

              const SizedBox(height: 6),

              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  void _openHistory(BuildContext context) {
    final bloc = context.read<InventoryBloc>();

    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: InventoryAdditionalHistoryDialog(branch: branch),
      ),
    );
  }
}
