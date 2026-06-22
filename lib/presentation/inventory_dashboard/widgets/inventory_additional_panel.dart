import 'package:daily_order/core/theme/app_colors.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/additional_request_group.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';

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
  final Map<String, TextEditingController> storeQtyControllers = {};
  final Map<String, TextEditingController> storeNoteControllers = {};
  final Map<String, bool> loadingMap = {};
  Future<void> _confirmAll(BuildContext context) async {
    final List<Map<String, dynamic>> bulk = [];

    for (var e in widget.requests) {
      if (!_isPending(e)) continue;

      final id = e.groupId;

      final fallbackQty = e.inventoryQty ?? e.requestQty ?? 0;
      final qty =
          num.tryParse(
            (qtyControllers[id]?.text ?? fallbackQty.toString()).trim(),
          ) ??
          0;

      final note = (noteControllers[id]?.text ?? '').trim();
      bulk.add({
        'id': id,
        'qty': qty,
        'inventory_qty': qty,
        'note': note,
        'inventory_note': note,
      });
    }

    if (bulk.isEmpty) return;

    context.read<InventoryBloc>().add(ApproveAllInventoryRequests(bulk));
  }

  @override
  Widget build(BuildContext context) {
    List<AdditionalRequestGroup> list = [...widget.requests];

    /// 🔥 GROUP BY PRODUCT
    final Map<String, List<AdditionalRequestGroup>> grouped = {};

    for (var r in list) {
      final key = '${r.itemCodes}_${_statusBucket(r)}';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(r);
    }

    final groupedList = grouped.values.toList();

    groupedList.sort((a, b) {
      int minA = a.map(_statusPriority).reduce((v, e) => v < e ? v : e);
      int minB = b.map(_statusPriority).reduce((v, e) => v < e ? v : e);

      if (minA != minB) return minA.compareTo(minB);

      DateTime latestA = a
          .where(_isPending)
          .map((e) => e.createdAt)
          .fold(DateTime(2000), (prev, e) => e.isAfter(prev) ? e : prev);

      DateTime latestB = b
          .where(_isPending)
          .map((e) => e.createdAt)
          .fold(DateTime(2000), (prev, e) => e.isAfter(prev) ? e : prev);

      return latestB.compareTo(latestA);
    });

    return BlocListener<InventoryBloc, InventoryState>(
      listenWhen: (previous, current) {
        return previous.isBulkLoading &&
            !current.isBulkLoading &&
            current.bulkSuccess != null;
      },
      listener: (context, state) {
        _showBulkSnackBar(context, success: state.bulkSuccess == true);
      },
      child: Container(
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
                    child: SelectableText(
                      "Inventory Additional Requests",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                  ),
                  BlocBuilder<InventoryBloc, InventoryState>(
                    builder: (context, state) {
                      return ElevatedButton(
                        onPressed: state.isBulkLoading
                            ? null
                            : () => _confirmAll(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                        ),
                        child: state.isBulkLoading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Confirm All Additional",
                                style: TextStyle(color: Colors.white),
                              ),
                      );
                    },
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
      ),
    );
  }

  void _showBulkSnackBar(BuildContext context, {required bool success}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: success ? const Color(0xff16A34A) : const Color(0xffDC2626),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  success ? Icons.check_rounded : Icons.close_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      success
                          ? 'All additional requests confirmed'
                          : 'Failed to confirm additional requests',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      success
                          ? 'The selected quantities and notes were sent successfully.'
                          : 'Please try again or check the connection.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _statusPriority(AdditionalRequestGroup e) {
    if (_isPending(e)) {
      if (e.contactLogistic == 'urgent') return 0;
      return 1;
    }

    if (e.status == 'sent_to_store') return 2;
    if (e.status == 'done') return 3;

    return 4;
  }

  bool _isPending(AdditionalRequestGroup e) {
    final status = e.status.toLowerCase().trim();
    return status == 'pending_inventory' || status == 'pending';
  }

  String _statusBucket(AdditionalRequestGroup e) {
    final status = e.status.toLowerCase().trim();
    if (status == 'pending_inventory' || status == 'pending') {
      return 'pending';
    }
    if (status == 'sent_to_store') return 'sent_to_store';
    if (status == 'done') return 'done';
    if (status == 'rejected') return 'rejected';
    return 'other';
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
      margin: EdgeInsets.symmetric(vertical: 6.h, horizontal: 5.w),
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
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  "${group.first.itemCodes} - ${group.first.itemNames}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),

              if (group.any((e) => e.contactLogistic == 'urgent'))
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const SelectableText(
                    "URGENT",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(group.first.status),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  group.first.status.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          /// ITEMS
          Column(
            children: group.map((e) {
              final id = e.groupId;

              storeQtyControllers.putIfAbsent(
                id,
                () => TextEditingController(
                  text: (e.fulfilledQty ?? 0).toString(),
                ),
              );

              storeNoteControllers.putIfAbsent(
                id,
                () => TextEditingController(text: e.storeNote ?? ''),
              );
              qtyControllers.putIfAbsent(
                id,
                () => TextEditingController(
                  text:
                      ((e.inventoryQty ?? 0) > 0
                              ? e.inventoryQty
                              : e.requestQty ?? 0)
                          .toString(),
                ),
              );

              noteControllers.putIfAbsent(
                id,
                () => TextEditingController(text: e.inventoryNote ?? ''),
              );

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
                              SelectableText(
                                e.branchName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SelectableText(
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
                        const SelectableText("Req: "),
                        SelectableText(
                          e.requestQty.toString(),
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(width: 15),
                        if (_isPending(e)) ...[
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
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
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
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (e.status == "sent_to_store" ||
                            e.status == "done") ...[
                          SizedBox(
                            width: 150.w,
                            child: TextField(
                              controller: qtyControllers[id],
                              readOnly: true,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                labelText: "Inventory Confirm",
                                labelStyle: TextStyle(
                                  color: AppColors.secondaryColor,
                                ),
                                filled: true,
                                fillColor: AppColors.backgroundWidget,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10.w),

                          SizedBox(
                            width: 150.w,
                            child: TextField(
                              controller: storeQtyControllers[id],
                              readOnly: true,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                labelText: "Store Supply",
                                labelStyle: TextStyle(
                                  color: AppColors.secondaryColor,
                                ),

                                filled: true,
                                fillColor: AppColors.backgroundWidget,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(width: 10.w),

                          SizedBox(
                            width: 225.w,
                            child: TextField(
                              controller: storeNoteControllers[id],
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: "Store Note",
                                labelStyle: TextStyle(
                                  color: AppColors.secondaryColor,
                                ),

                                filled: true,
                                fillColor: AppColors.backgroundWidget,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 6),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundWidget,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _infoBox("Branch Stock", e.branchStock),
                          _infoBox("Store Stock", e.storeStock),
                          _infoBox("Sales", e.sales),
                          _infoBox("Final Reorder", e.finalReorder),
                          _infoBox("Today Req", e.todayCount),
                          _infoBox("Item Status", e.itemStatus),
                          Spacer(),
                          if (_isPending(e)) ...[
                            SizedBox(width: 5.w),

                            BlocListener<InventoryBloc, InventoryState>(
                              listener: (context, state) {
                                setState(() {
                                  loadingMap.clear();
                                });
                              },
                              child: ElevatedButton(
                                onPressed: loadingMap[id] == true
                                    ? null
                                    : () async {
                                        setState(() {
                                          loadingMap[id] = true;
                                        });

                                        final qty =
                                            int.tryParse(
                                              qtyControllers[id]?.text ?? '0',
                                            ) ??
                                            0;

                                        context.read<InventoryBloc>().add(
                                          ApproveInventoryRequest(
                                            requestId: e.groupId,
                                            qty: qty,
                                            note:
                                                noteControllers[id]?.text
                                                    .trim() ??
                                                '',
                                          ),
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                child: loadingMap[id] == true
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        "Approve",
                                        style: TextStyle(color: Colors.white),
                                      ),
                              ),
                            ),
                          ],
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
        SelectableText(
          title,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 3),
        SelectableText(
          _formatInfoValue(title, value),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

String _formatInfoValue(String title, dynamic value) {
  if (value == null) return '-';

  if (title == 'Sales') {
    final n = value is num
        ? value
        : num.tryParse(value.toString().replaceAll(',', ''));

    if (n == null) return value.toString();

    return n.toStringAsFixed(2);
  }

  return value.toString();
}
