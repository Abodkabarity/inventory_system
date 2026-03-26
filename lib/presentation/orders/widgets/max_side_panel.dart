import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';

class MaxSidePanel extends StatefulWidget {
  const MaxSidePanel({super.key});

  @override
  State<MaxSidePanel> createState() => _MaxSidePanelState();
}

class _MaxSidePanelState extends State<MaxSidePanel> {
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    context.read<OrdersBloc>().add(const OrdersLoadMaxAdj());
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.white,
        elevation: 20,
        child: SizedBox(
          width: screenWidth * 0.5,
          child: Column(
            children: [
              /// HEADER
              BlocBuilder<OrdersBloc, OrdersState>(
                builder: (context, state) {
                  final count = state.maxAdjItems.length;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    color: AppColors.primaryColor,
                    child: Row(
                      children: [
                        Text(
                          "Max Adjustment ($count / 15)",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),

                        const Spacer(),

                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const _AddMaxForm(),

              const Divider(),

              /// SEARCH
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: "Search...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppColors.backgroundWidget,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              /// LIST
              Expanded(
                child: BlocBuilder<OrdersBloc, OrdersState>(
                  builder: (context, state) {
                    final isLoading = state.isMaxAdjLoading;

                    return Stack(
                      children: [
                        ListView.builder(
                          itemCount: state.maxAdjItems.length,
                          itemBuilder: (_, i) {
                            return _MaxRow(
                              index: i,
                              item: state.maxAdjItems[i],
                            );
                          },
                        ),

                        if (isLoading)
                          const Center(child: CircularProgressIndicator()),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddMaxForm extends StatefulWidget {
  const _AddMaxForm();

  @override
  State<_AddMaxForm> createState() => _AddMaxFormState();
}

class _AddMaxFormState extends State<_AddMaxForm> {
  final code = TextEditingController();
  final name = TextEditingController();

  final demand = TextEditingController(); // 🔥 NEW
  final maxQty = TextEditingController(); // 🔥 NEW (هو qty)

  final reason = TextEditingController();

  String type = "INCREASE";

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrdersBloc>().state;
    final isFull = state.maxAdjItems.length >= 15;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          /// ITEM
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: "Item Code"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: "Item Name"),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          /// DEMAND + MAX
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: demand,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Current Demand (30d)",
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: maxQty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Max Adjustment (30d)",
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          /// TYPE
          DropdownButtonFormField<String>(
            value: type,
            items: const [
              DropdownMenuItem(value: "INCREASE", child: Text("INCREASE")),
              DropdownMenuItem(value: "DECREASE", child: Text("DECREASE")),
            ],
            onChanged: (v) => setState(() => type = v!),
          ),

          const SizedBox(height: 10),

          /// REASON
          TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: "Reason"),
          ),

          const SizedBox(height: 12),

          /// ADD BUTTON
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isFull ? Colors.grey : AppColors.primaryColor,
              minimumSize: const Size(double.infinity, 45),
            ),
            onPressed: isFull
                ? null
                : () {
                    final demandVal = num.tryParse(demand.text) ?? 0;

                    final maxVal = num.tryParse(maxQty.text) ?? 0;

                    if (code.text.isEmpty || name.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Select item first")),
                      );
                      return;
                    }

                    /// 🔥 qty = max
                    final qty = maxVal;

                    context.read<OrdersBloc>().add(
                      OrdersAddMaxAdj({
                        'branch_name': context
                            .read<OrdersBloc>()
                            .state
                            .branchName,

                        'item_code': code.text,
                        'item_name': name.text,

                        'current_demand_30d': demandVal,
                        'max_adjustment_30d': maxVal,

                        'qty': qty, // 🔥 AUTO

                        'adjustment_type': type,
                        'reason': reason.text,
                      }),
                    );

                    /// CLEAR
                    code.clear();
                    name.clear();
                    demand.clear();
                    maxQty.clear();
                    reason.clear();
                  },
            child: Text(
              isFull ? "Limit Reached (15)" : "Add Max",
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaxRow extends StatelessWidget {
  final Map item;
  final int index;

  const _MaxRow({required this.item, required this.index});

  Color _getColor(String type) {
    return type == "INCREASE" ? Colors.green : Colors.red;
  }

  String _format(dynamic v) {
    if (v == null) return "0";
    if (v is num) {
      if (v % 1 == 0) return v.toInt().toString();
      return v.toStringAsFixed(2);
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final type = (item['adjustment_type'] ?? '').toString();

    final demand = item['current_demand_30d'];
    final maxAdj = item['max_adjustment_30d'];
    final qty = item['qty'];
    final reason = (item['reason'] ?? '').toString();

    return Card(
      color: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            /// 🔢 INDEX
            SizedBox(
              width: 35,
              child: Text(
                "${index + 1}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),

            /// ITEM INFO
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['item_name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['item_code'] ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),

                  const SizedBox(height: 8),

                  /// 🔥 EXTRA DATA
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _chip("Demand", _format(demand), Colors.blue),
                      _chip("Max 30d", _format(maxAdj), Colors.orange),
                      _chip("Qty", _format(qty), Colors.purple),
                    ],
                  ),

                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      "Reason: $reason",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            /// TYPE + DELETE
            Column(
              children: [
                /// TYPE
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getColor(type).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      color: _getColor(type),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                /// DELETE
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    _showDeleteDialog(
                      context,
                      item['id'].toString(),
                      item['item_name'],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        "$title: $value",
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

void _showDeleteDialog(BuildContext context, String id, String itemName) {
  showDialog(
    context: context,
    builder: (_) {
      return AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("Confirm Delete"),
        content: Text("Are you sure you want to delete \"$itemName\"?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Cancel",
              style: TextStyle(color: AppColors.secondaryColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<OrdersBloc>().add(OrdersDeleteMaxAdj(id));
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    },
  );
}
