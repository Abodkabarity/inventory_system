import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../inventory_dashboard/bloc/inventory_bloc.dart';
import '../../inventory_dashboard/bloc/inventory_state.dart';
import '../../inventory_dashboard/widgets/inventory_additional_request_dialog.dart';

class InventoryAdditionalHistoryDialog extends StatefulWidget {
  final String branch;

  const InventoryAdditionalHistoryDialog({super.key, required this.branch});

  @override
  State<InventoryAdditionalHistoryDialog> createState() =>
      _InventoryAdditionalHistoryDialogState();
}

class _InventoryAdditionalHistoryDialogState
    extends State<InventoryAdditionalHistoryDialog> {
  late DateTime from;
  late DateTime to;

  late DateTime defaultFrom;
  late DateTime defaultTo;

  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    defaultFrom = DateTime(now.year, now.month, 1);
    defaultTo = now;

    from = defaultFrom;
    to = defaultTo;
  }

  /// DATE RANGE PICKER
  Future<void> pickDateRange() async {
    List<DateTime?> values = [from, to];

    final result = await showDialog<List<DateTime?>>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                /// HEADER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Select Date Range",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                CalendarDatePicker2(
                  config: CalendarDatePicker2Config(
                    calendarType: CalendarDatePicker2Type.range,
                    selectedDayHighlightColor: AppColors.primaryColor,
                    selectedRangeHighlightColor: AppColors.primaryColor,
                  ),
                  value: values,
                  onValueChanged: (dates) {
                    values = dates;
                  },
                ),

                const Divider(),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        if (values.length >= 2 &&
                            values.first != null &&
                            values.last != null) {
                          Navigator.pop(context, values);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                      ),
                      child: const Text("Apply"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        from = result.first!;
        to = result.last!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: Colors.grey.shade100,
      child: Container(
        width: 780,
        height: 520,
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            /// HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${widget.branch} Additional History",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            /// FILTER BAR
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: pickDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                        color: AppColors.white,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            "${DateFormat('yyyy-MM-dd').format(from)} → ${DateFormat('yyyy-MM-dd').format(to)}",
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search item / code",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: AppColors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            /// LIST
            Expanded(
              child: BlocBuilder<InventoryBloc, InventoryState>(
                builder: (context, state) {
                  var list = state.additionalRequests.where((e) {
                    if (e.branchName != widget.branch) return false;

                    if (e.createdAt.isBefore(from)) return false;

                    if (e.createdAt.isAfter(to)) return false;

                    final q = searchController.text.toLowerCase();

                    if (q.isNotEmpty &&
                        !e.itemNames.toLowerCase().contains(q) &&
                        !e.itemCodes.toLowerCase().contains(q)) {
                      return false;
                    }

                    return true;
                  }).toList();

                  if (list.isEmpty) {
                    return const Center(child: Text("No orders found"));
                  }

                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final r = list[i];

                      return GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => InventoryAdditionalRequestDialog(
                              groupId: r.groupId,
                              branch: widget.branch,
                            ),
                          );
                        },
                        child: _historyCard(r),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// CARD DESIGN

  Widget _historyCard(dynamic r) {
    Color color;
    String text;

    switch (r.status) {
      case "pending_inventory":
        color = Colors.orange;
        text = "PENDING INVENTORY";
        break;

      case "sent_to_store":
        color = Colors.blue;
        text = "SENT TO STORE";
        break;

      case "done":
        color = Colors.green;
        text = "DONE";
        break;

      case "rejected":
        color = Colors.red;
        text = "REJECTED";
        break;

      default:
        color = Colors.grey;
        text = r.status;
    }

    final itemsCount = r.itemCodes == null || r.itemCodes.isEmpty
        ? r.itemsCount
        : r.itemCodes.split(',').length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline),

          const SizedBox(width: 12),

          /// ORDER INFO
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${r.branchName} Additional Order",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(DateFormat("yyyy-MM-dd HH:mm").format(r.createdAt)),
              ],
            ),
          ),

          /// ITEMS COUNT
          Text(
            "$itemsCount items",
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),

          const SizedBox(width: 12),

          /// STATUS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
