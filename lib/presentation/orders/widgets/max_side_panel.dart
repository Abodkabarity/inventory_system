import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
    searchController.clear();

    context.read<OrdersBloc>().add(const OrdersSearchMaxAdjList(''));
    context.read<OrdersBloc>().add(const OrdersLoadMaxAdj());
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return SelectionArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.white,
          elevation: 20,
          child: SizedBox(
            width: screenWidth * 0.5.w,
            child: Column(
              children: [
                /// HEADER
                BlocBuilder<OrdersBloc, OrdersState>(
                  builder: (context, state) {
                    final usedSlots = state.usedMaxAdjSlots;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      color: AppColors.primaryColor,
                      child: Row(
                        children: [
                          Text(
                            "Max Adjustment ($usedSlots / ${state.maxAdjLimit})",
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

                const Divider(
                  color: AppColors.secondaryColor,
                  endIndent: 100,
                  indent: 100,
                ),

                /// SEARCH
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: "Search...",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: AppColors.backgroundWidget,
                      labelStyle: TextStyle(color: AppColors.secondaryColor),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primaryColor),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primaryColor),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primaryColor),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onChanged: (v) {
                      context.read<OrdersBloc>().add(OrdersSearchMaxAdjList(v));
                    },
                  ),
                ),

                /// LIST
                Expanded(
                  child: BlocBuilder<OrdersBloc, OrdersState>(
                    builder: (context, state) {
                      final isLoading = state.isMaxAdjLoading;

                      final query = state.maxAdjSearch.toLowerCase();

                      final filtered = state.maxAdjItems.where((e) {
                        final code = (e['item_code'] ?? '')
                            .toString()
                            .toLowerCase();
                        final name = (e['item_name'] ?? '')
                            .toString()
                            .toLowerCase();

                        final matchSearch =
                            code.contains(query) || name.contains(query);

                        if (state.onlyBranchMaxAdj) {
                          return matchSearch && e['added_by'] == 'branch';
                        }

                        return matchSearch;
                      }).toList();

                      return Stack(
                        children: [
                          ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              return _MaxRow(index: i, item: filtered[i]);
                            },
                          ),

                          if (isLoading)
                            const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primaryColor,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
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
  final _formKey = GlobalKey<FormState>();
  bool submitted = false;

  final code = TextEditingController();
  final name = TextEditingController();
  final demand = TextEditingController();
  final maxQty = TextEditingController();
  final reason = TextEditingController();

  final codeLink = LayerLink();
  final nameLink = LayerLink();

  final codeFocus = FocusNode();
  final nameFocus = FocusNode();

  OverlayEntry? overlayEntry;
  String activeField = '';

  String type = "INCREASE";

  @override
  void dispose() {
    removeOverlay();
    codeFocus.dispose();
    nameFocus.dispose();
    super.dispose();
  }

  void showOverlay(BuildContext context, OrdersState state, OrdersBloc bloc) {
    removeOverlay();

    final link = activeField == 'code' ? codeLink : nameLink;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  removeOverlay();
                  codeFocus.unfocus();
                  nameFocus.unfocus();
                },
              ),
            ),
            Positioned(
              width: 400.w,
              child: CompositedTransformFollower(
                link: link,
                offset: const Offset(0, 55),
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4.h,
                    ),
                    child: ListView.builder(
                      itemCount: state.mismatchSuggestions.length,
                      itemBuilder: (_, i) {
                        final e = state.mismatchSuggestions[i];

                        return ListTile(
                          title: Text(e['item_name']),
                          subtitle: Text(e['item_code']),
                          onTap: () {
                            code.text = e['item_code'];
                            name.text = e['item_name'];

                            bloc.add(OrdersFetchItemDemand(e['item_code']));
                            print(state.selectedItemDemand);
                            bloc.add(OrdersSearchMismatchItemsCode(''));

                            removeOverlay();
                            codeFocus.unfocus();
                            nameFocus.unfocus();
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(overlayEntry!);
  }

  void removeOverlay() {
    overlayEntry?.remove();
    overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrdersBloc>().state;

    final usedSlots = state.usedMaxAdjSlots;

    final remainingSlots = state.remainingMaxAdjSlots;

    final isFull = remainingSlots <= 0;
    final nextDate = state.nextAvailableDate;

    final nextDays = state.daysUntilNextSlot;
    return BlocListener<OrdersBloc, OrdersState>(
      listenWhen: (prev, curr) =>
          prev.mismatchSuggestions != curr.mismatchSuggestions ||
          prev.selectedItemDemand != curr.selectedItemDemand ||
          prev.showMismatchResult != curr.showMismatchResult,

      listener: (context, state) {
        if (state.mismatchSuggestions.isNotEmpty &&
            (codeFocus.hasFocus || nameFocus.hasFocus)) {
          showOverlay(context, state, context.read<OrdersBloc>());
        } else {
          removeOverlay();
        }

        demand.text = state.selectedItemDemand.toString();
        if (state.showMismatchResult == true &&
            state.lastActionSuccess == false &&
            state.error != null &&
            state.error!.isNotEmpty) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Cannot Add Max Adjustment'),
              content: Text(state.error!),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          autovalidateMode: submitted
              ? AutovalidateMode.always
              : AutovalidateMode.disabled,
          child: Column(
            children: [
              /// ITEM WITH SEARCH 🔥
              Row(
                children: [
                  Expanded(
                    child: CompositedTransformTarget(
                      link: codeLink,
                      child: TextFormField(
                        focusNode: codeFocus,
                        controller: code,
                        decoration: InputDecoration(
                          labelText: "Item Code",
                          labelStyle: TextStyle(
                            color: AppColors.secondaryColor,
                          ),
                          filled: true,
                          fillColor: AppColors.backgroundWidget,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? "Required" : null,
                        onChanged: (v) {
                          activeField = 'code';
                          context.read<OrdersBloc>().add(
                            OrdersSearchMismatchItemsCode(v),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CompositedTransformTarget(
                      link: nameLink,
                      child: TextFormField(
                        focusNode: nameFocus,
                        controller: name,
                        decoration: InputDecoration(
                          labelText: "Item Name",
                          labelStyle: TextStyle(
                            color: AppColors.secondaryColor,
                          ),
                          filled: true,
                          fillColor: AppColors.backgroundWidget,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),

                            borderRadius: BorderRadius.circular(14),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? "Required" : null,
                        onChanged: (v) {
                          activeField = 'name';
                          context.read<OrdersBloc>().add(
                            OrdersSearchMismatchItemsName(v),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 10.h),

              /// DEMAND + MAX
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: demand,
                      readOnly: true,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Current Demand",
                        labelStyle: TextStyle(color: AppColors.secondaryColor),
                        filled: true,
                        fillColor: AppColors.backgroundWidget,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return "Required";
                        if (num.tryParse(v) == null) return "Invalid number";
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: maxQty,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: "Max Adjustment",
                        labelStyle: TextStyle(color: AppColors.secondaryColor),
                        filled: true,
                        fillColor: AppColors.backgroundWidget,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return "Required";
                        if (num.tryParse(v) == null) return "Invalid number";
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              SizedBox(height: 10.h),

              TextFormField(
                controller: reason,
                decoration: InputDecoration(
                  labelText: "Reason",
                  labelStyle: TextStyle(color: AppColors.secondaryColor),
                  filled: true,
                  fillColor: AppColors.backgroundWidget,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primaryColor),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primaryColor),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primaryColor),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),

              SizedBox(height: 12.h),

              Row(
                children: [
                  Container(
                    width: 175.w,
                    height: 50.h,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundWidget,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Added By Branch"),
                        Switch(
                          value: state.onlyBranchMaxAdj,
                          activeThumbColor: AppColors.primaryColor,
                          onChanged: (v) {
                            context.read<OrdersBloc>().add(
                              OrdersToggleBranchMaxAdj(v),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          minimumSize: const Size(300, 40),
                        ),
                        onPressed: () {
                          setState(() {
                            submitted = true;
                          });

                          if (!_formKey.currentState!.validate()) {
                            return;
                          }
                          final state = context.read<OrdersBloc>().state;

                          final alreadyExists = state.maxAdjItems.any(
                            (e) =>
                                e['item_code'] == code.text &&
                                e['status'] != 'removed',
                          );

                          if (alreadyExists) {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: const Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.orange,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Already Exists'),
                                  ],
                                ),
                                content: const Text(
                                  'This item already exists in Max list.',
                                ),
                                actions: [
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.close,
                                      color: AppColors.secondaryColor,
                                    ),
                                    label: const Text(
                                      'Close',
                                      style: TextStyle(
                                        color: AppColors.secondaryColor,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                            );

                            return;
                          }
                          final demandVal = num.tryParse(demand.text) ?? 0;
                          final maxVal = num.tryParse(maxQty.text) ?? 0;
                          final type = maxVal < demandVal
                              ? "DECREASE"
                              : "INCREASE";
                          if (type == 'INCREASE' && isFull) {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Limit Reached'),
                                content: Text(
                                  'You reached the maximum allowed Max Adjustments '
                                  '(${state.maxAdjLimit}).',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );

                            return;
                          }
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
                              'qty': maxVal,
                              'adjustment_type': type,
                              'reason': reason.text,
                              'added_by': 'branch',
                            }),
                          );
                          context.read<OrdersBloc>().add(
                            const OrdersClearSelectedDemand(),
                          );
                          _formKey.currentState!.reset();

                          code.clear();
                          name.clear();
                          demand.clear();
                          maxQty.clear();
                          reason.clear();

                          setState(() {
                            submitted = false;
                          });
                        },
                        child: const Text(
                          "Add Max",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: SizedBox()),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isFull && nextDays != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              children: [
                                Text(
                                  'Next slot available in $nextDays day(s)',
                                  textAlign: TextAlign.center,

                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Available on $nextDate',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
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

class _MaxRow extends StatelessWidget {
  final Map item;
  final int index;

  const _MaxRow({required this.item, required this.index});

  Color _getColor(String type, bool isRemoved) {
    if (isRemoved) {
      return Colors.grey;
    }

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

  String getRemainingDays(Map item) {
    try {
      final updateDateStr = (item['update_date'] ?? '').toString();

      final endDateStr = (item['end_date'] ?? '').toString();

      final adjustmentType = (item['adjustment_type'] ?? '')
          .toString()
          .toUpperCase();

      final isRemoved = item['status'] == 'removed';

      final now = DateTime.now();

      DateTime expiryDate;

      if (endDateStr.isNotEmpty && endDateStr != 'null' && !isRemoved) {
        expiryDate = DateTime.parse(endDateStr);
      } else {
        final updateDate = DateTime.parse(updateDateStr);

        final durationDays = isRemoved
            ? 30
            : (adjustmentType == 'DECREASE' ? 45 : 30);

        expiryDate = updateDate.add(Duration(days: durationDays));
      }

      final daysLeft = expiryDate.difference(now).inDays;

      if (daysLeft <= 0) {
        return 'Expired';
      }

      return '$daysLeft Days Left';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final demand = item['current_demand_30d'];
    final maxAdj = item['max_adjustment_30d'];

    final demandVal = (demand is num) ? demand : num.tryParse('$demand') ?? 0;
    final maxVal = (maxAdj is num) ? maxAdj : num.tryParse('$maxAdj') ?? 0;

    final type = maxVal < demandVal ? "DECREASE" : "INCREASE";

    final qty = item['qty'];
    final reason = (item['reason'] ?? '').toString();
    final remainingDays = getRemainingDays(item);
    final isRemoved = item['status'] == 'removed';
    return Card(
      color: Colors.white,
      elevation: 3,
      shadowColor: AppColors.secondaryColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.primaryColor),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            /// 🔢 INDEX
            SizedBox(
              width: 35.w,
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
                  SizedBox(height: 4.h),
                  Text(
                    item['item_code'] ?? '',
                    style: TextStyle(color: Colors.grey, fontSize: 12.sp),
                  ),

                  SizedBox(height: 8.h),

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

                  if (reason.isNotEmpty)
                    if (isRemoved)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Removed by Branch',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      "Reason: $reason",
                      style: TextStyle(fontSize: 12.sp, color: Colors.black87),
                    ),
                  ),

                  if (remainingDays.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        remainingDays,
                        style: TextStyle(
                          color: remainingDays == 'Expired'
                              ? Colors.red
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
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
                    color: _getColor(type, isRemoved).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isRemoved ? 'REMOVED' : type,
                    style: TextStyle(
                      color: _getColor(type, isRemoved),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                SizedBox(height: 10.h),

                /// DELETE
                if (!isRemoved)
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
