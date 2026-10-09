import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../../widgets/app_date_range_picker_dialog.dart';

class MismatchTrackerDialog extends StatefulWidget {
  const MismatchTrackerDialog({super.key});

  @override
  State<MismatchTrackerDialog> createState() => _MismatchTrackerDialogState();
}

class _MismatchTrackerDialogState extends State<MismatchTrackerDialog> {
  late DateTime from;
  late DateTime to;

  String search = "";
  String branch = "ALL";

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    from = DateTime(now.year, now.month, now.day);
    to = now;

    _load();
  }

  void _load() {
    context.read<InventoryBloc>().add(
      LoadMismatchTracker(
        from: from,
        to: to.add(const Duration(days: 1)),
        branch: branch == "ALL" ? null : branch,
      ),
    );
  }

  /// ================= DATE PICKER =================
  Future<void> pickDateRange() async {
    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => AppDateRangePickerDialog(
        initialRange: DateTimeRange(start: from, end: to),
        lastDate: DateTime(9999),
        allowSingleDay: true,
      ),
    );
    if (result == null || !mounted) return;
    final sameRange = DateUtils.isSameDay(result.start, from) &&
        DateUtils.isSameDay(result.end, to);
    setState(() {
      from = sameRange ? from : result.start;
      to = sameRange ? to : result.end;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final branches = context.read<InventoryBloc>().state.branches;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 1200,
        height: 700,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _header(),
            const SizedBox(height: 12),
            _filters(branches),
            const SizedBox(height: 12),
            Expanded(child: _list()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "Mismatch Tracker",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _filters(List<String> branches) {
    return Row(
      children: [
        /// 🔍 Search
        Expanded(
          child: TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              hintText: "Search...",
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),

        const SizedBox(width: 10),

        /// 📅 Date Range
        InkWell(
          onTap: pickDateRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(),
            ),
            child: Row(
              children: [
                const Icon(Icons.date_range),
                const SizedBox(width: 6),
                Text(
                  "${DateFormat('dd MMM').format(from)} → ${DateFormat('dd MMM').format(to)}",
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 10),

        /// 🏢 Branch Filter
        DropdownButton<String>(
          value: branch,
          items: [
            "ALL",
            ...branches,
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) {
            setState(() => branch = v!);
            _load();
          },
        ),
      ],
    );
  }

  Widget _list() {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        var data = state.mismatchTracker;

        if (search.isNotEmpty) {
          data = data.where((e) {
            return e['item_name'].toString().toLowerCase().contains(
                  search.toLowerCase(),
                ) ||
                e['item_code'].toString().toLowerCase().contains(
                  search.toLowerCase(),
                );
          }).toList();
        }

        return ListView.builder(
          itemCount: data.length,
          itemBuilder: (_, i) {
            final e = data[i];

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e['item_name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text("Branch: ${e['branch_name']}"),

                    const SizedBox(height: 6),

                    if (e['old_actual_stock'] != null)
                      Text("OLD: ${e['old_actual_stock']}"),

                    if (e['new_actual_stock'] != null)
                      Text("NEW: ${e['new_actual_stock']}"),

                    if (e['action'] == 'update')
                      Text(
                        "${e['old_actual_stock']} → ${e['new_actual_stock']}",
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                    Text(
                      DateFormat(
                        'yyyy-MM-dd HH:mm',
                      ).format(DateTime.parse(e['changed_at'])),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
