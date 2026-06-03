// items_to_order_dialog.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

  final _qtyController = TextEditingController(text: '1');

  final _reasonController = TextEditingController();

  Timer? _debounce;

  Map<String, dynamic>? selectedItem;

  List<Map<String, dynamic>> suggestions = [];

  bool loading = false;

  @override
  void dispose() {
    _debounce?.cancel();

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

    context.read<OrdersBloc>().add(
      OrdersAddItemToOrder(
        itemCode: selectedItem!['item_code'].toString(),
        itemName: selectedItem!['item_name'].toString(),
        qty: qty,
        reason: _reasonController.text.trim(),
      ),
    );

    _searchController.clear();
    _qtyController.text = '1';
    _reasonController.clear();

    selectedItem = null;

    context.read<OrdersBloc>().add(
      const OrdersLoadItemsToOrder(),
    );

    setState(() {});  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),

      child: Container(
        width: 800,
        padding: const EdgeInsets.all(24),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart, size: 28),

                const SizedBox(width: 12),

                const Expanded(
                  child: Text(
                    'Items To Order',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                ),

                IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),

            const SizedBox(height: 20),

            TextField(
              controller: _searchController,

              decoration: InputDecoration(
                hintText: 'Search item code or item name',

                prefixIcon: const Icon(Icons.search),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),

              onChanged: (value) {
                _debounce?.cancel();

                _debounce = Timer(const Duration(milliseconds: 350), () {
                  _search(value);
                });
              },
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
                margin: const EdgeInsets.only(top: 16),

                padding: const EdgeInsets.all(12),

                decoration: BoxDecoration(
                  color: const Color(0xfff4f8fb),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        '${selectedItem!['item_code']} - ${selectedItem!['item_name']}',
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _qtyController,

                    keyboardType: TextInputType.number,

                    decoration: InputDecoration(
                      labelText: 'Qty',

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _reasonController,

                    maxLines: 2,

                    decoration: InputDecoration(
                      labelText: 'Reason',

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            BlocBuilder<OrdersBloc, OrdersState>(
              builder: (context, state) {

                if (state.itemsToOrder.isEmpty) {
                  return const SizedBox();
                }

                return Flexible(
                  child: Container(
                    constraints: const BoxConstraints(
                      maxHeight: 250,
                    ),

                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: state.itemsToOrder.length,

                      itemBuilder: (_, index) {

                        final item =
                        state.itemsToOrder[index];

                        return Card(
                          child: ListTile(
                            title: Text(
                              item.itemName,
                            ),

                            subtitle: Text(
                              '${item.itemCode}\n'
                                  'Qty: ${item.qty}\n'
                                  '${item.reason}',
                            ),

                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.red,
                              ),

                              onPressed: () async {

                                context.read<OrdersBloc>().add(
                                  OrdersDeleteItemToOrder(
                                    item.id,
                                  ),
                                );

                                await Future.delayed(
                                  const Duration(milliseconds: 300),
                                );

                                if (!context.mounted) return;

                                context.read<OrdersBloc>().add(
                                  const OrdersLoadItemsToOrder(),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,

              children: [
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),

                const SizedBox(width: 12),

                ElevatedButton.icon(
                  onPressed: _addItem,

                  icon: const Icon(Icons.add),

                  label: const Text('Add Item'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
