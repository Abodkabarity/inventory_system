// items_to_order_dialog.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';

class ItemsToOrderDialog extends StatefulWidget {
  const ItemsToOrderDialog({super.key});

  @override
  State<ItemsToOrderDialog> createState() => _ItemsToOrderDialogState();
}

class _ItemsToOrderDialogState extends State<ItemsToOrderDialog> {
  final _searchController = TextEditingController();
  final _requestedByController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');

  final _reasonController = TextEditingController();

  Timer? _debounce;

  Map<String, dynamic>? selectedItem;

  List<Map<String, dynamic>> suggestions = [];

  bool loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _requestedByController.dispose();
    _searchController.dispose();
    _qtyController.dispose();
    _reasonController.dispose();

    super.dispose();
  }

  Future<void> _search(String value) async {
    if (value.trim().length < 2) {
      setState(() {
        suggestions = [];
      });
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final result = await context
          .read<OrdersBloc>()
          .repo
          .searchItemsToOrderSuggestions(value);

      if (!mounted) return;

      setState(() {
        suggestions = result;
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _addItem() async {
    if (selectedItem == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select item')));
      return;
    }

    final qty = num.tryParse(_qtyController.text) ?? 0;

    if (qty <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid quantity')));
      return;
    }

    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reason required')));
      return;
    }
    if (_requestedByController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Requested By required')));
      return;
    }
    context.read<OrdersBloc>().add(
      OrdersAddItemToOrder(
        itemCode: selectedItem!['item_code'].toString(),
        itemName: selectedItem!['item_name'].toString(),
        qty: qty,
        reason: _reasonController.text.trim(),
        requestedBy: _requestedByController.text.trim(),
      ),
    );

    _searchController.clear();
    _qtyController.text = '1';
    _reasonController.clear();
    _requestedByController.clear();
    selectedItem = null;

    context.read<OrdersBloc>().add(const OrdersLoadItemsToOrder());

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 6.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),

        child: Container(
          width: 1200.w,
          height: 800.h,
          padding: const EdgeInsets.all(24),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
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
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.shopping_cart_outlined,
                        color: AppColors.primaryColor,
                      ),
                    ),

                    const SizedBox(width: 14),

                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Items To Order',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Create additional item requests',
                            style: TextStyle(color: Colors.grey),
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

              const SizedBox(height: 20),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xffF7F8FC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _searchController,

                  onChanged: (value) {
                    _debounce?.cancel();

                    _debounce = Timer(
                      const Duration(milliseconds: 400),
                      () => _search(value),
                    );
                  },

                  decoration: InputDecoration(
                    hintText: 'Search item code or item name',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppColors.backgroundWidget,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: AppColors.primaryColor),
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: AppColors.primaryColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: AppColors.primaryColor),
                    ),
                    contentPadding: const EdgeInsets.all(18),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              if (loading) const LinearProgressIndicator(),

              if (suggestions.isNotEmpty)
                Container(
                  height: 220,

                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),

                    borderRadius: BorderRadius.circular(12),
                  ),

                  child: ListView.builder(
                    itemCount: suggestions.length,

                    itemBuilder: (_, index) {
                      final item = suggestions[index];

                      return ListTile(
                        title: Text(item['item_name']?.toString() ?? ''),

                        subtitle: Text(item['item_code']?.toString() ?? ''),

                        onTap: () {
                          setState(() {
                            selectedItem = item;

                            _searchController.text =
                                '${item['item_code']} - ${item['item_name']}';

                            suggestions = [];
                          });
                        },
                      );
                    },
                  ),
                ),

              if (selectedItem != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedItem!['item_name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            Text(
                              selectedItem!['item_code'],
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 5),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: SizedBox(
                      height: 64,
                      child: TextField(
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        maxLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          labelText: 'Qty',

                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          filled: true,
                          fillColor: AppColors.backgroundWidget,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                          ),

                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 64,
                      child: TextField(
                        controller: _reasonController,
                        maxLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          labelText: 'Reason',

                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),

                          filled: true,
                          fillColor: AppColors.backgroundWidget,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                          ),

                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: TextField(
                        controller: _requestedByController,
                        decoration: InputDecoration(
                          labelText: 'Requested By *',
                          prefixIcon: const Icon(Icons.person_outline),

                          filled: true,
                          fillColor: AppColors.backgroundWidget,

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: AppColors.primaryColor,
                            ),
                          ),

                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: AppColors.primaryColor,
                            ),
                          ),

                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              BlocBuilder<OrdersBloc, OrdersState>(
                builder: (context, state) {
                  if (state.itemsToOrder.isEmpty) {
                    return const SizedBox();
                  }

                  return Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: state.itemsToOrder.length,

                      itemBuilder: (_, index) {
                        final item = state.itemsToOrder[index];
                        final status = item.status.toLowerCase();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),

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
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          item.itemCode,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 20),

                                        Text(
                                          item.itemName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),

                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.person,
                                          size: 15,
                                          color: Colors.grey,
                                        ),

                                        const SizedBox(width: 10),

                                        Text(
                                          item.requestedBy ?? '-',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(width: 4),

                                    const SizedBox(height: 8),

                                    Row(
                                      spacing: 10,
                                      children: [
                                        Chip(
                                          avatar: const Icon(
                                            Icons.inventory_2_outlined,
                                            size: 16,
                                            color: AppColors.primaryColor,
                                          ),
                                          label: Text('Qty ${item.qty}'),
                                        ),

                                        Chip(
                                          avatar: const Icon(
                                            Icons.notes,
                                            size: 16,
                                            color: AppColors.primaryColor,
                                          ),
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

                                            const SizedBox(width: 4),

                                            Text(
                                              item.createdAtFormatted,
                                              style: const TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              if (status == 'pending')
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red,
                                    ),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          backgroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          title: const Row(
                                            children: [
                                              Icon(
                                                Icons.delete_forever,
                                                color: Colors.red,
                                              ),
                                              SizedBox(width: 10),
                                              Text('Delete Item'),
                                            ],
                                          ),
                                          content: Text(
                                            'Delete "${item.itemName}" ?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(context, false);
                                              },
                                              child: const Text(
                                                'Cancel',
                                                style: TextStyle(
                                                  color:
                                                      AppColors.secondaryColor,
                                                ),
                                              ),
                                            ),
                                            FilledButton.icon(
                                              icon: const Icon(Icons.delete),
                                              label: const Text('Delete'),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: Colors.red,
                                              ),
                                              onPressed: () {
                                                Navigator.pop(context, true);
                                              },
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm != true) return;

                                      if (!context.mounted) return;

                                      context.read<OrdersBloc>().add(
                                        OrdersDeleteItemToOrder(item.id),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
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
                          side: BorderSide(color: AppColors.primaryColor),
                        ),
                        side: const BorderSide(color: Color(0xffD9DCE8)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.secondaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: AppColors.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _addItem,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Add Request',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
