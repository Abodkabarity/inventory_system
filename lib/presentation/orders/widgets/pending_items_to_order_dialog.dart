import 'package:flutter/material.dart';

import '../../../data/models/item_to_order_model.dart';

class PendingItemsToOrderDialog extends StatelessWidget {
  final List<ItemToOrder> items;

  const PendingItemsToOrderDialog({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),

      child: Container(
        width: 1000,
        height: 700,

        padding: const EdgeInsets.all(24),

        child: Column(
          children: [
            const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 30,
                ),

                SizedBox(width: 12),

                Text(
                  'Pending Items To Order',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Text(
              '${items.length} pending suggestions need review before submit',
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView.separated(
                itemCount: items.length,

                separatorBuilder: (_, __) => const Divider(),

                itemBuilder: (_, index) {
                  final item = items[index];

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            item.itemName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(item.itemCode),

                          const SizedBox(height: 10),

                          Text('Qty : ${item.qty}'),

                          const SizedBox(height: 6),

                          Text('Reason : ${item.reason}'),

                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.add),

                                  label: const Text('Add To Order'),

                                  onPressed: () {
                                    Navigator.pop(context, {
                                      'action': 'add',
                                      'item': item,
                                    });
                                  },
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.close),

                                  label: const Text('Ignore'),

                                  onPressed: () {
                                    Navigator.pop(context, {
                                      'action': 'ignore',
                                      'item': item,
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            FilledButton(
              onPressed: () {
                Navigator.pop(context, 'continue');
              },
              child: const Text('Skip All And Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
