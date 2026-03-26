import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
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

    /// load edits
    context.read<InventoryBloc>().add(LoadBranchAnalytics(widget.branch));

    /// load additional stats
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
        height: screen.height * 0.85,
        padding: const EdgeInsets.all(24),

        child: BlocBuilder<InventoryBloc, InventoryState>(
          builder: (context, state) {
            /// ============================
            /// ADDITIONAL
            /// ============================

            final additionalToday = state.additionalRequests
                .where(
                  (e) =>
                      e.branchName == widget.branch &&
                      DateUtils.isSameDay(e.createdAt, DateTime.now()),
                )
                .length;

            final additionalMonth =
                state.additionalMonthBranchCount[widget.branch] ?? 0;

            /// ============================
            /// EDITS
            /// ============================

            final editsToday = state.editsCount[widget.branch] ?? 0;

            final editsMonth = state.edits.length;

            return Column(
              children: [
                /// ============================
                /// HEADER
                /// ============================
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

                const SizedBox(height: 25),

                /// ============================
                /// KPI CARDS
                /// ============================
                Row(
                  children: [
                    _kpiCard(
                      title: "Additional Today",
                      value: additionalToday,
                      color: Colors.orange,
                      onTap: () => _openHistory(context),
                    ),

                    _kpiCard(
                      title: "Additional Month",
                      value: additionalMonth,
                      color: Colors.deepOrange,
                      onTap: () => _openHistory(context),
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

                const SizedBox(height: 30),

                /// ============================
                /// TITLE
                /// ============================
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Edited Products Today",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 10),

                /// ============================
                /// EDITS LIST
                /// ============================
                Expanded(
                  child: state.edits.isEmpty
                      ? const Center(
                          child: Text(
                            "No edits today",
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          itemCount: state.edits.length,
                          itemBuilder: (context, i) {
                            final item = state.edits[i];

                            return Card(
                              elevation: 4,
                              margin: const EdgeInsets.only(bottom: 10),

                              child: ListTile(
                                leading: const Icon(
                                  Icons.edit,
                                  color: AppColors.primaryColor,
                                ),

                                title: Text(
                                  item.itemName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),

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
