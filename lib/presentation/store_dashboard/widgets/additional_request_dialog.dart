import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/print_additional_service.dart';

class AdditionalRequestDialog extends StatefulWidget {
  final String groupId;
  final String branch;

  const AdditionalRequestDialog({
    super.key,
    required this.groupId,
    required this.branch,
  });

  @override
  State<AdditionalRequestDialog> createState() =>
      _AdditionalRequestDialogState();
}

class _AdditionalRequestDialogState extends State<AdditionalRequestDialog> {
  final client = Supabase.instance.client;

  List<Map<String, dynamic>> items = [];

  bool loading = true;
  bool approved = false;

  final Map<String, TextEditingController> qtyControllers = {};
  final Map<String, TextEditingController> noteControllers = {};

  /// ✅ NEW: processing state
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final res = await client
        .from('additional_requests')
        .select()
        .eq('request_group_id', widget.groupId)
        .order('item_name');

    items = List<Map<String, dynamic>>.from(res);

    items = items.where((e) {
      final inv = e['inventory_qty'];

      if (inv == null) return true;

      return inv > 0;
    }).toList();

    if (items.isNotEmpty) {
      final status = items.first['status'] ?? '';
      approved = status == 'done' || status == 'rejected';

      /// ✅ IMPORTANT FIX
      isProcessing = items.any((e) => e['store_status'] == 'processing');
    }

    for (var item in items) {
      final id = item['id'].toString();

      final inventoryQty = item['inventory_qty'];
      final fulfilledQty = item['fulfilled_qty'];
      final requestQty = item['request_qty'];

      final qty = inventoryQty ?? fulfilledQty ?? requestQty ?? 0;

      qtyControllers[id] = TextEditingController(text: qty.toString());

      noteControllers[id] = TextEditingController(
        text: (item['store_note'] ?? '').toString(),
      );
    }

    setState(() {
      loading = false;
    });
  }

  Future<void> _printAndProcess() async {
    try {
      final Map<String, List<Map<String, dynamic>>> batch = {
        widget.branch: items,
      };

      await PrintAdditionalService.printBatch(batch);

      for (var item in items) {
        final id = item['id'];

        await client
            .from('additional_requests')
            .update({'store_status': 'processing'})
            .eq('id', id);

        /// ✅ update local
        item['store_status'] = 'processing';
      }

      setState(() {
        approved = true;
        isProcessing = true;
      });
    } catch (e) {
      print("PRINT + UPDATE ERROR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey.shade100,
      child: Container(
        width: 950,
        height: 620,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  "${widget.branch} Additional Order",
                  style: const TextStyle(
                    fontSize: 20,
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

            const Divider(color: AppColors.primaryColor),

            if (loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryColor,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  children: [for (var item in items) _buildItem(item)],
                ),
              ),

            const SizedBox(height: 10),

            /// ✅ FIXED CONDITION
            if (approved || isProcessing)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: items.any((e) => e['status'] == 'rejected')
                      ? Colors.red.shade100
                      : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      items.any((e) => e['status'] == 'rejected')
                          ? Icons.cancel
                          : Icons.check_circle,
                      color: items.any((e) => e['status'] == 'rejected')
                          ? Colors.red
                          : Colors.green,
                    ),
                    const SizedBox(width: 10),

                    /// ✅ FIXED TEXT
                    Text(
                      isProcessing
                          ? "Already Print"
                          : items.any((e) => e['status'] == 'rejected')
                          ? "Rejected"
                          : "Done",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            Align(
              alignment: Alignment.centerRight,
              child: (approved)
                  ? ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                      ),
                      child: const Text(
                        "Close",
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _printAndProcess,
                      icon: const Icon(Icons.print, color: AppColors.white),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                      ),
                      label: const Text(
                        "Print",
                        style: TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final id = item['id'].toString();

    return Card(
      color: Colors.white,
      shadowColor: AppColors.primaryColor,
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "${item['item_code'] ?? ''}",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 30),
                Text(
                  item['item_name'] ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            Row(
              children: [
                const Text("Requested: "),
                Text(
                  "${item['inventory_qty'] ?? item['request_qty'] ?? 0}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(width: 20),

                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: qtyControllers[id],
                    readOnly: approved || isProcessing,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondaryColor,
                    ),
                    decoration: InputDecoration(
                      labelText: "Sent Qty",
                      filled: true,
                      fillColor: AppColors.backgroundWidget,
                      labelStyle: const TextStyle(
                        color: AppColors.secondaryColor,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primaryColor,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 20),

                Expanded(
                  child: TextField(
                    controller: noteControllers[id],
                    readOnly: approved || isProcessing,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondaryColor,
                    ),
                    decoration: InputDecoration(
                      labelText: "Store Note",
                      filled: true,
                      fillColor: AppColors.backgroundWidget,
                      labelStyle: const TextStyle(
                        color: AppColors.secondaryColor,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primaryColor,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
