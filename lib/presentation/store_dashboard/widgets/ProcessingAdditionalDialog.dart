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

  final Map<String, TextEditingController> qtyControllers = {};
  final Map<String, TextEditingController> noteControllers = {};
  final TextEditingController searchController = TextEditingController();

  final Map<String, bool> itemLoading = {};

  bool printLoading = false;

  String? successMessage;

  List<Map<String, dynamic>> allItems = [];

  /// 🔥 GROUP FUNCTION
  Map<String, List<Map<String, dynamic>>> groupByBranch(
    List<Map<String, dynamic>> items,
  ) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var item in items) {
      final branch = item['branch_name'] ?? '';
      grouped.putIfAbsent(branch, () => []);
      grouped[branch]!.add(item);
    }

    return grouped;
  }

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

  /// 🔥 PRINT
  Future<void> _printBranch(
    String branch,
    List<Map<String, dynamic>> items,
  ) async {
    setState(() => printLoading = true);

    try {
      final Map<String, List<Map<String, dynamic>>> single = {branch: items};
      await PrintAdditionalService.printBatch(single);
    } catch (e) {
      print("PRINT ERROR: $e");
    }

    setState(() => printLoading = false);
  }

  /// 🔥 CONFIRM
  Future<void> _confirmItem(Map<String, dynamic> item) async {
    final id = item['id'];
    final key = id.toString();

    setState(() {
      itemLoading[key] = true;
    });

    try {
      final qty = num.tryParse(qtyControllers[key]!.text.trim()) ?? 0;
      final note = noteControllers[key]!.text;

      final status = qty == 0 ? 'rejected' : 'done';

      await client
          .from('additional_requests')
          .update({
            'inventory_qty': qty,
            'fulfilled_qty': qty,
            'store_note': note,
            'status': status, // ✅ FIX
            'store_status': 'done',
            'done_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .select();
      context.read<StoreBloc>().add(RefreshProcessingList());
      setState(() {
        allItems.removeWhere((e) => e['id'] == id);
        successMessage = "Confirmed successfully";
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            successMessage = null;
          });
        }
      });
    } catch (e) {
      print("CONFIRM ERROR: $e");
    }

    setState(() {
      itemLoading[key] = false;
    });
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final requestQty = item['request_qty'] ?? 0;

    final isLoading = itemLoading[id] == true;
    if (!qtyControllers.containsKey(id)) {
      final qty =
          item['inventory_qty'] ??
          item['fulfilled_qty'] ??
          item['request_qty'] ??
          0;

      qtyControllers[id] = TextEditingController(text: qty.toString());

      noteControllers[id] = TextEditingController(
        text: (item['store_note'] ?? '').toString(),
      );
    }
    return Card(
      color: Colors.white,
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  onPressed: isLoading
                      ? null
                      : () {
                          qtyControllers[id]!.text = "0";
                          noteControllers[id]!.text = "Out of Stock";
                          setState(() {});
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text(
                    "Out Of Stock",
                    style: TextStyle(color: Colors.white),
                  ),
                ),

                const SizedBox(width: 10),

                /// CONFIRM
                ElevatedButton(
                  onPressed: isLoading ? null : () => _confirmItem(item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "Confirm",
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranch(String branch, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                onPressed: printLoading
                    ? null
                    : () => _printBranch(branch, items),
                icon: printLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.print, size: 18, color: Colors.white),
                label: Text(
                  printLoading ? "Printing..." : "Print $branch Additional",
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                ),
              ),
            ],
          ),
        ),
        ...items.map(_buildItem),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = context.select((StoreBloc bloc) => bloc.state.filteredList);

    final grouped = groupByBranch(list);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (list.isEmpty && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    return Dialog(
      backgroundColor: Colors.grey.shade100,
      child: Container(
        width: 1100,
        height: 650,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (successMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        successMessage!,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const Row(
              children: [
                Text(
                  "Processing Additional Orders",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: TextField(
                controller: searchController,
                onChanged: (v) => context.read<StoreBloc>().add(
                  SearchProcessingItems(query: v),
                ),
                decoration: InputDecoration(
                  hintText: "Search product...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.backgroundWidget,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primaryColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primaryColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primaryColor),
                  ),
                ),
              ),
            ),

            const Divider(color: AppColors.primaryColor),

            Expanded(
              child: grouped.isEmpty
                  ? const Center(child: Text("No results"))
                  : ListView(
                      children: grouped.entries
                          .map((e) => _buildBranch(e.key, e.value))
                          .toList(),
                    ),
            ),

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
