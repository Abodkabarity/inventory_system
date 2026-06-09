import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/item_to_order_model.dart';

class PendingItemsToOrderDialog extends StatefulWidget {
  final List<ItemToOrder> items;

  final Future<String?> Function(ItemToOrder item) onAddPressed;

  final Future<void> Function(ItemToOrder item) onIgnorePressed;

  const PendingItemsToOrderDialog({
    super.key,
    required this.items,
    required this.onAddPressed,
    required this.onIgnorePressed,
  });

  @override
  State<PendingItemsToOrderDialog> createState() =>
      _PendingItemsToOrderDialogState();
}

class _PendingItemsToOrderDialogState extends State<PendingItemsToOrderDialog> {
  late final int initialCount;

  final Map<String, String> decisions = {};

  @override
  void initState() {
    super.initState();
    initialCount = widget.items.length;
  }

  bool get allReviewed {
    return widget.items.every((e) {
      final status = decisions[e.id] ?? e.status;

      return status == 'ignored' || status == 'processed';
    });
  }

  @override
  Widget build(BuildContext context) {
    final reviewed = widget.items.where((e) {
      final status = decisions[e.id] ?? e.status;

      return status == 'ignored' || status == 'processed';
    }).length;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 900.w,
        height: 800,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            /// HEADER
            Container(
              padding: const EdgeInsets.only(bottom: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xffECECEC))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pending Items To Order',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),

                            Text(
                              '$initialCount pending suggestions need review',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        SizedBox(width: 50.w),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'Reviewed $reviewed / $initialCount',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: ListView.builder(
                itemCount: widget.items.length,
                itemBuilder: (_, index) {
                  final item = widget.items[index];

                  final status =
                      decisions[item.id] ?? item.status.toLowerCase();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xffEAEAEA)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.03),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              item.itemCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 15),

                            Text(
                              item.itemName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        if (item.requestedBy != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.person_outline,
                                size: 15,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                item.requestedBy!,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 10),

                        Row(
                          spacing: 10,
                          children: [
                            Chip(
                              avatar: const Icon(
                                Icons.inventory_2_outlined,
                                size: 16,
                              ),
                              label: Text('Qty ${item.qty}'),
                            ),

                            Chip(
                              avatar: const Icon(Icons.notes, size: 16),
                              label: Text(item.reason),
                            ),

                            Chip(
                              backgroundColor: status == 'pending'
                                  ? Colors.orange.shade50
                                  : status == 'ignored'
                                  ? Colors.red.shade50
                                  : Colors.green.shade50,

                              avatar: Icon(
                                status == 'pending'
                                    ? Icons.hourglass_empty
                                    : status == 'ignored'
                                    ? Icons.cancel
                                    : Icons.check_circle,
                                size: 16,
                                color: status == 'pending'
                                    ? Colors.orange
                                    : status == 'ignored'
                                    ? Colors.red
                                    : Colors.green,
                              ),

                              label: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: status == 'pending'
                                      ? Colors.orange
                                      : status == 'ignored'
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 15,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  item.createdAt.toString(),
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        if (status == 'pending')
                          Row(
                            children: [
                              SizedBox(
                                width: 250.w,
                                height: 40.h,
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text(
                                    'Add To Order',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    backgroundColor: AppColors.primaryColor,
                                  ),
                                  onPressed: () async {
                                    final result = await widget.onAddPressed(
                                      item,
                                    );

                                    if (!mounted) return;

                                    if (result == 'added' ||
                                        result == 'processed') {
                                      setState(() {
                                        decisions[item.id] = 'processed';
                                      });
                                    }
                                  },
                                ),
                              ),

                              const SizedBox(width: 12),

                              SizedBox(
                                width: 250.w,
                                height: 40.h,
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Ignore',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () async {
                                    await widget.onIgnorePressed(item);

                                    if (!mounted) return;

                                    setState(() {
                                      decisions[item.id] = 'ignored';
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(color: AppColors.primaryColor),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: AppColors.primaryColor,
                    ),
                    icon: const Icon(Icons.arrow_forward, color: Colors.white),
                    label: const Text(
                      'Next',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    onPressed: allReviewed
                        ? () {
                            Navigator.pop(context, true);
                          }
                        : null,
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
