import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';

class InventoryAdditionalRequestDialog extends StatefulWidget {
  final String groupId;
  final String branch;

  const InventoryAdditionalRequestDialog({
    super.key,
    required this.groupId,
    required this.branch,
  });

  @override
  State<InventoryAdditionalRequestDialog> createState() =>
      _InventoryAdditionalRequestDialogState();
}

class _InventoryAdditionalRequestDialogState
    extends State<InventoryAdditionalRequestDialog> {
  final client = Supabase.instance.client;

  List<Map<String, dynamic>> items = [];

  bool loading = true;

  String status = 'pending';

  final Map<String, TextEditingController> qtyControllers = {};
  final Map<String, TextEditingController> noteControllers = {};

  final Set<String> expandedRows = {};
  final Set<String> loadingRows = {};

  final Map<String, Map<String, dynamic>> itemDetails = {};

  bool get isEditable => status == 'pending';

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

    if (items.isNotEmpty) {
      status = items.first['status'] ?? 'pending_inventory';
    }

    for (var item in items) {
      final id = item['id'].toString();

      qtyControllers[id] = TextEditingController(
        text: item['request_qty'].toString(),
      );

      noteControllers[id] = TextEditingController(
        text: (item['inventory_note'] ?? '').toString(),
      );
    }

    setState(() {
      loading = false;
    });
  }

  Future<void> _loadItemDetails(Map<String, dynamic> item) async {
    final id = item['id'].toString();
    final itemCode = item['item_code'];
    final branch = widget.branch;

    loadingRows.add(id);
    setState(() {});

    final res = await client
        .from('daily_order')
        .select(
          'branch_stock,store_stock,demand_for_30_days,final_reorder_qty_store_stock_gt_0,qty_30_days_from_last_45d,item_purchase_type',
        )
        .eq('branch', branch)
        .eq('item_code', itemCode)
        .maybeSingle();

    final totalSales = await client
        .from('daily_order')
        .select('qty_30_days_from_last_45d')
        .eq('item_code', itemCode);

    double total = 0;

    for (var r in totalSales) {
      total += (r['qty_30_days_from_last_45d'] ?? 0);
    }

    itemDetails[itemCode] = {
      "branch_stock": res?['branch_stock'] ?? 0,
      "store_stock": res?['store_stock'] ?? 0,
      "demand": res?['demand_for_30_days'] ?? 0,
      "final_reorder": res?['final_reorder_qty_store_stock_gt_0'] ?? 0,
      "branch_sales": res?['qty_30_days_from_last_45d'] ?? 0,
      "total_sales": total,
      "purchase_type": res?['item_purchase_type'] ?? "",
    };

    loadingRows.remove(id);
    setState(() {});
  }

  Future<void> _approveInventory() async {
    for (var item in items) {
      final id = item['id'].toString();

      final qty = num.tryParse(qtyControllers[id]!.text.trim()) ?? 0;
      final note = noteControllers[id]!.text;

      await client
          .from('additional_requests')
          .update({
            'inventory_qty': qty,
            'inventory_note': note,
            'inventory_approved_at': DateTime.now().toIso8601String(),
            'status': 'sent_to_store',
          })
          .eq('id', id);
    }

    setState(() {
      status = 'sent_to_store';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey.shade100,
      child: Container(
        width: 1000,
        height: 650,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  "${widget.branch} Additional Request",
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
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(children: items.map(_buildItem).toList()),
              ),

            const SizedBox(height: 10),

            _buildStatusBanner(),

            const SizedBox(height: 10),

            Align(
              alignment: Alignment.centerRight,
              child: isEditable
                  ? ElevatedButton.icon(
                      onPressed: _approveInventory,
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text(
                        "Approve & Send to Store",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    if (status == 'pending_inventory') return const SizedBox();

    Color color;
    IconData icon;
    String text;

    switch (status) {
      case 'sent_to_store':
        color = Colors.blue;
        icon = Icons.local_shipping;
        text = "Sent to Store";
        break;

      case 'rejected':
        color = Colors.red;
        icon = Icons.cancel;
        text = "Request Rejected";
        break;

      case 'done':
        color = Colors.green;
        icon = Icons.check_circle;
        text = "Request Completed";
        break;

      default:
        return const SizedBox();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final itemCode = item['item_code'];

    final expanded = expandedRows.contains(id);
    final loadingRow = loadingRows.contains(id);

    return Column(
      children: [
        Card(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () async {
                    if (expanded) {
                      expandedRows.remove(id);
                    } else {
                      expandedRows.add(id);
                      await _loadItemDetails(item);
                    }
                    setState(() {});
                  },
                ),

                Expanded(
                  flex: 4,
                  child: Text(
                    "${item['item_code']}  ${item['item_name']}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),

                Expanded(
                  child: Text(
                    "Req: ${item['request_qty']}",
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: qtyControllers[id],
                    enabled: isEditable,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(labelText: "Qty"),
                  ),
                ),

                const SizedBox(width: 20),

                Expanded(
                  child: TextField(
                    controller: noteControllers[id],
                    enabled: isEditable,
                    decoration: const InputDecoration(
                      labelText: "Inventory Note",
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (expanded && loadingRow)
          const Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ),

        if (expanded && !loadingRow) _buildExpandedInfo(itemCode),
      ],
    );
  }

  Widget _buildExpandedInfo(String itemCode) {
    if (!itemDetails.containsKey(itemCode)) return const SizedBox();

    final data = itemDetails[itemCode]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 4,
        ),
        children: [
          _info("Branch Stock", data["branch_stock"]),
          _info("Store Stock", data["store_stock"]),
          _info("Demand", data["demand"]),
          _info("Final Reorder", data["final_reorder"]),
          _info("Branch Sales", data["branch_sales"]),
          _info("Total Sales", data["total_sales"]),
          _info("Purchase Type", data["purchase_type"]),
        ],
      ),
    );
  }

  Widget _info(String title, dynamic value) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(
              "$title : ",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(value.toString()),
          ],
        ),
      ),
    );
  }
}
