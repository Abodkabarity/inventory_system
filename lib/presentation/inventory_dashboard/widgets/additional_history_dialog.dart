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
          backgroundColor: Colors.white,
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

                /// RANGE DISPLAY
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range),
                      const SizedBox(width: 10),
                      Text(
                        "${DateFormat("dd MMM yyyy").format(values.first!)}  →  ${DateFormat("dd MMM yyyy").format(values.last!)}",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                /// CALENDAR
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

                /// BUTTONS
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.red),
                      ),
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
                      child: const Text(
                        "Apply",
                        style: TextStyle(color: AppColors.white),
                      ),
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
        width: 760,
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
                            style: const TextStyle(fontSize: 13),
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
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.primaryColor,
                      ),
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
                  var list = state.additionalRequests
                      .where((e) => e.branchName == widget.branch)
                      .toList();

                  final query = searchController.text.toLowerCase();

                  if (query.isNotEmpty) {
                    list = list.where((e) {
                      return e.itemNames.toLowerCase().contains(query) ||
                          e.itemCodes.toLowerCase().contains(query);
                    }).toList();
                  }

                  if (list.isEmpty) {
                    return const Center(child: Text("No orders found"));
                  }

                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final r = list[i];
                      return _historyCard(r);
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

  Widget _historyCard(dynamic r) {
    Color statusColor;
    String statusText;

    switch (r.status) {
      case "sent_to_store":
        statusColor = Colors.green;
        statusText = "SENT";
        break;

      case "rejected":
        statusColor = Colors.red;
        statusText = "REJECTED";
        break;

      default:
        statusColor = Colors.orange;
        statusText = "PENDING";
    }

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(
          r.itemNames,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          "${r.itemCodes}\n${DateFormat("yyyy-MM-dd HH:mm").format(r.createdAt)}",
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            statusText,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => InventoryAdditionalRequestDialog(
              groupId: r.groupId,
              branch: widget.branch,
            ),
          );
        },
      ),
    );
  }
}
