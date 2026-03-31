import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/print_additional_service.dart';
import '../bloc/store_bloc.dart';
import '../bloc/store_event.dart';

class ProcessingAdditionalDialog extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> data;

  const ProcessingAdditionalDialog({super.key, required this.data});

  @override
  State<ProcessingAdditionalDialog> createState() =>
      _ProcessingAdditionalDialogState();
}

class _ProcessingAdditionalDialogState
    extends State<ProcessingAdditionalDialog> {
  final client = Supabase.instance.client;

  bool loading = false;

  final Map<String, TextEditingController> qtyControllers = {};
  final Map<String, TextEditingController> noteControllers = {};
  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> allItems = [];

  @override
  void initState() {
    super.initState();

    for (var branch in widget.data.keys) {
      for (var item in widget.data[branch]!) {
        allItems.add(item);

        final id = item['id'].toString();
        final qty = item['request_qty'] ?? 0;

        qtyControllers[id] = TextEditingController(text: qty.toString());
        noteControllers[id] = TextEditingController(text: '');
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StoreBloc>().add(SearchProcessingItems(query: ''));
    });
  }

  /// 🔥 PRINT FOR ONE BRANCH
  void _printBranch(String branch, List<Map<String, dynamic>> items) async {
    final Map<String, List<Map<String, dynamic>>> single = {branch: items};
    await PrintAdditionalService.printBatch(single);
  }

  Future<void> _confirmItem(Map<String, dynamic> item) async {
    final id = item['id'].toString();
    final requestQty = item['request_qty'] ?? 0;

    final qty = num.tryParse(qtyControllers[id]!.text.trim()) ?? 0;
    final note = noteControllers[id]!.text;

    String status;

    if (qty == 0) {
      status = 'rejected';
    } else if (qty < requestQty) {
      status = 'partial';
    } else {
      status = 'done';
    }

    await client
        .from('additional_requests')
        .update({
          'inventory_qty': qty,
          'fulfilled_qty': qty,
          'store_note': note,
          'status': status,
          'store_status': 'done',
          'done_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);

    setState(() {
      allItems.removeWhere((e) => e['id'].toString() == id);
    });
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final requestQty = item['request_qty'] ?? 0;

    return Card(
      color: Colors.white,
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// HEADER
            Row(
              children: [
                Text(
                  "${item['item_code']}",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    item['item_name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                const Text("Requested: "),
                Text(
                  "$requestQty",
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(width: 20),

                /// QTY
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: qtyControllers[id],
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: "Qty",
                      filled: true,
                      fillColor: AppColors.backgroundWidget,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 15),

                /// NOTE
                Expanded(
                  child: TextField(
                    controller: noteControllers[id],
                    decoration: InputDecoration(
                      labelText: "Store Note",
                      filled: true,
                      fillColor: AppColors.backgroundWidget,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                /// OUT
                ElevatedButton(
                  onPressed: () {
                    qtyControllers[id]!.text = "0";
                    noteControllers[id]!.text = "Out of Stock";
                    setState(() {});
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text("Out"),
                ),

                const SizedBox(width: 10),

                /// CONFIRM
                ElevatedButton(
                  onPressed: () => _confirmItem(item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text("Confirm"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranch(String branch, List<Map<String, dynamic>> items) {
    final branchItems = items
        .where((e) => allItems.any((a) => a['id'] == e['id']))
        .toList();

    if (branchItems.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// HEADER
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                branch,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryColor,
                ),
              ),

              ElevatedButton.icon(
                onPressed: () => _printBranch(branch, branchItems),
                icon: const Icon(Icons.print, size: 18),
                label: Text("Print $branch Additional"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),

        ...branchItems.map(_buildItem),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<StoreBloc>().state;

    final dataToShow = state.filteredProcessing;

    return Dialog(
      backgroundColor: Colors.grey.shade100,
      child: Container(
        width: 1100,
        height: 650,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            /// HEADER
            Row(
              children: const [
                Text(
                  "Processing Additional Orders",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),

            /// 🔍 SEARCH
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: "Search product...",
                  prefixIcon: Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  context.read<StoreBloc>().add(
                    SearchProcessingItems(query: value),
                  );
                },
              ),
            ),

            const Divider(color: AppColors.primaryColor),

            /// BODY
            Expanded(
              child: dataToShow.isEmpty
                  ? const Center(
                      child: Text(
                        "No results",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    )
                  : ListView(
                      children: dataToShow.entries
                          .map((e) => _buildBranch(e.key, e.value))
                          .toList(),
                    ),
            ),

            /// CLOSE
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                ),
                child: const Text(
                  "Close",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
