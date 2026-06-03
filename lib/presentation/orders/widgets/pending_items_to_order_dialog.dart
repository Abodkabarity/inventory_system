import 'package:flutter/material.dart';

import '../../../data/models/item_to_order_model.dart';

class PendingItemsToOrderDialog extends StatefulWidget {
  final List<ItemToOrder> items;

  final Future<bool> Function(
      ItemToOrder item,
      ) onAddPressed;

  const PendingItemsToOrderDialog({
    super.key,
    required this.items, required this.onAddPressed,
  });

  @override
  State<PendingItemsToOrderDialog> createState() =>
      _PendingItemsToOrderDialogState();
}

class _PendingItemsToOrderDialogState
    extends State<PendingItemsToOrderDialog> {
  final Map<String, String> decisions = {};

  Map<String, dynamic> buildResult() {
    return {
      'decisions': decisions,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
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
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Text(
              '${widget.items.length} pending suggestions need review before submit',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView.separated(
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = widget.items[index];

                  final status = decisions[item.itemCode];

                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.itemName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            item.itemCode,
                            style: const TextStyle(
                              color: Colors.grey,
                            ),
                          ),

                          const SizedBox(height: 12),

                          Text(
                            'Qty : ${item.qty}',
                            style: const TextStyle(
                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            'Reason : ${item.reason}',
                            style: const TextStyle(
                              fontSize: 16,
                            ),
                          ),

                          const SizedBox(height: 12),

                          if (status == 'added')
                            Row(
                              children: const [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 28,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Added To Order',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight:
                                    FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),

                          if (status == 'ignored')
                            Row(
                              children: const [
                                Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                  size: 28,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Ignored',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight:
                                    FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),

                          const SizedBox(height: 16),

                          if (status == null)
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.add,
                                    ),
                                    label: const Text(
                                      'Add To Order',
                                    ),
                                      onPressed: () async {

                                        final result =
                                        await widget.onAddPressed(item);

                                        if (!mounted) return;

                                        if (result == true) {
                                          setState(() {
                                            decisions[item.itemCode] = 'added';
                                          });
                                        }
                                      },
                                  ),
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child:
                                  OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.close,
                                    ),
                                    label:
                                    const Text('Ignore'),
                                    onPressed: () {
                                      setState(() {
                                        decisions[item.itemCode] =
                                        'ignored';
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

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel'),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: FilledButton.icon(
                    icon:
                    const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                    onPressed: () {
                      Navigator.pop(
                        context,
                        buildResult(),
                      );
                    },
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