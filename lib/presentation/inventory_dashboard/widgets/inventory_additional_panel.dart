import 'package:daily_order/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/additional_request_group.dart';

class InventoryAdditionalPanel extends StatefulWidget {
  final List<AdditionalRequestGroup> requests;

  const InventoryAdditionalPanel({super.key, required this.requests});

  @override
  State<InventoryAdditionalPanel> createState() =>
      _InventoryAdditionalPanelState();
}

class _InventoryAdditionalPanelState extends State<InventoryAdditionalPanel> {
  final Map<String, TextEditingController> qtyControllers = {};
  final Map<String, TextEditingController> noteControllers = {};

  @override
  Widget build(BuildContext context) {
    List<AdditionalRequestGroup> list = [...widget.requests];

    /// 🔥 GROUP BY PRODUCT
    final Map<String, List<AdditionalRequestGroup>> grouped = {};

    for (var r in list) {
      grouped.putIfAbsent(r.itemCodes, () => []);
      grouped[r.itemCodes]!.add(r);
    }

    final groupedList = grouped.values.toList();

    groupedList.sort((a, b) {
      int minA = a.map(_statusPriority).reduce((v, e) => v < e ? v : e);
      int minB = b.map(_statusPriority).reduce((v, e) => v < e ? v : e);

      if (minA != minB) return minA.compareTo(minB);

      DateTime latestA = a
          .where((e) => e.status == 'pending')
          .map((e) => e.createdAt)
          .fold(DateTime(2000), (prev, e) => e.isAfter(prev) ? e : prev);

      DateTime latestB = b
          .where((e) => e.status == 'pending')
          .map((e) => e.createdAt)
          .fold(DateTime(2000), (prev, e) => e.isAfter(prev) ? e : prev);

      return latestB.compareTo(latestA);
    });
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundWidget,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          /// HEADER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Text(
                    "Inventory Additional Requests",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondaryColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(() {}),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: const Divider(color: AppColors.primaryColor),
          ),

          Expanded(
            child: ListView.builder(
              itemCount: groupedList.length,
              itemBuilder: (context, i) {
                return _buildProductCard(groupedList[i]);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 🔥 ترتيب دقيق جداً
  int _statusPriority(AdditionalRequestGroup e) {
    if (e.contactLogistic == 'urgent') return 0;
    if (e.status == 'pending') return 1;
    if (e.status == 'sent_to_store') return 2;
    if (e.status == 'done') return 3;
    return 4;
  }

  Widget _buildProductCard(List<AdditionalRequestGroup> group) {
    group.sort((a, b) {
      final pa = _statusPriority(a);
      final pb = _statusPriority(b);

      if (pa != pb) return pa.compareTo(pb);

      if (a.status == 'pending' && b.status == 'pending') {
        return b.createdAt.compareTo(a.createdAt);
      }

      return 0;
    });

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// HEADER
          Text(
            "${group.first.itemCodes} - ${group.first.itemNames}",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),

          const SizedBox(height: 10),

          /// ITEMS
          Column(
            children: group.map((e) {
              final id = e.groupId;

              qtyControllers.putIfAbsent(
                id,
                () => TextEditingController(text: "0"),
              );

              noteControllers.putIfAbsent(id, () => TextEditingController());

              return Padding(
                key: ValueKey(id),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        /// BRANCH + DATE
                        SizedBox(
                          width: 110.w,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.branchName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                DateFormat("yyyy-MM-dd HH:mm").format(
                                  e.createdAt.toLocal().add(
                                    const Duration(hours: 0),
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        /// REQ
                        const Text("Req: "),
                        Text(
                          e.requestQty.toString(),
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(width: 15),
                        if (e.status == "pending") ...[
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
                                  borderRadius: BorderRadius.circular(10),
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
                                labelText: "Inventory Note",
                                filled: true,
                                fillColor: AppColors.backgroundWidget,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),

                        if (e.contactLogistic == 'urgent')
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              "URGENT",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),

                        /// STATUS
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(e.status),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            e.status.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        if (e.status == "pending") ...[
                          const SizedBox(width: 5),

                          ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text(
                              "Reject",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),

                          const SizedBox(width: 5),

                          ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text(
                              "Approve",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 6),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          _infoBox("Branch", e.branchStock),
                          _infoBox("Store", e.storeStock),
                          _infoBox("Sales", e.sales),
                          _infoBox("Final", e.finalReorder),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

Color _getStatusColor(String status) {
  switch (status) {
    case "sent_to_store":
      return Colors.blue;
    case "done":
      return Colors.green;
    case "rejected":
      return Colors.red;
    default:
      return Colors.orange;
  }
}

Widget _infoBox(String title, dynamic value) {
  return Expanded(
    child: Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 3),
        Text(
          value.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    ),
  );
}
