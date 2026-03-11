import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      final status = items.first['status'] ?? '';
      approved = status == 'done';
    }

    for (var item in items) {
      final id = item['id'].toString();

      qtyControllers[id] = TextEditingController(
        text: (item['fulfilled_qty'] ?? item['request_qty']).toString(),
      );

      noteControllers[id] = TextEditingController(
        text: (item['store_note'] ?? '').toString(),
      );
    }

    setState(() {
      loading = false;
    });
  }

  Future<void> _approveAll() async {
    for (var item in items) {
      final id = item['id'].toString();

      final qty = num.tryParse(qtyControllers[id]!.text) ?? 0;
      final note = noteControllers[id]!.text;

      await client
          .from('additional_requests')
          .update({
            'fulfilled_qty': qty,
            'store_note': note,
            'status': 'done',
            'done_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
    }

    setState(() {
      approved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
            const Divider(),
            if (loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(
                  children: [for (var item in items) _buildItem(item)],
                ),
              ),
            const SizedBox(height: 10),
            if (approved)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 10),
                    Text(
                      "Request Approved",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: approved
                  ? ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                    )
                  : ElevatedButton.icon(
                      onPressed: _approveAll,
                      icon: const Icon(Icons.check),
                      label: const Text("Approve Request"),
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['item_name'] ?? '',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text("Requested: ${item['request_qty']}"),
                const SizedBox(width: 20),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: qtyControllers[id],
                    readOnly: approved,
                    decoration: const InputDecoration(labelText: "Sent Qty"),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: TextField(
                    controller: noteControllers[id],
                    readOnly: approved,
                    decoration: const InputDecoration(labelText: "Store Note"),
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
