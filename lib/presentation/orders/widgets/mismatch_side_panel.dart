import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';

class MismatchSidePanel extends StatefulWidget {
  const MismatchSidePanel({super.key});

  @override
  State<MismatchSidePanel> createState() => _MismatchSidePanelState();
}

class _MismatchSidePanelState extends State<MismatchSidePanel> {
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    context.read<OrdersBloc>().add(const OrdersLoadMismatch());
    context.read<OrdersBloc>().add(OrdersSearchMismatchList(''));
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
                  final count = state.mismatchItems.length;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    color: AppColors.primaryColor,
                    child: Row(
                      children: [
                        Text(
                          "Mismatch Items ($count)",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),

                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            context.read<OrdersBloc>().add(
                              OrdersSearchMismatchList(''),
                            );
                            searchController.clear();
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),

              const _AddForm(),
              const Divider(
                color: AppColors.secondaryColor,
                endIndent: 100,
                indent: 100,
              ),

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
                      borderSide: BorderSide(color: AppColors.primaryColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.primaryColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.primaryColor),
                    ),
                  ),
                  onChanged: (v) {
                    context.read<OrdersBloc>().add(OrdersSearchMismatchList(v));
                  },
                ),
              ),

              /// LIST + LOADING
              Expanded(
                child: BlocBuilder<OrdersBloc, OrdersState>(
                  builder: (context, state) {
                    final isLoading = state.isMismatchLoading;
                    final query = state.mismatchSearch.toLowerCase();

                    final filtered = state.mismatchItems.where((e) {
                      final code = (e['item_code'] ?? '')
                          .toString()
                          .toLowerCase();
                      final name = (e['item_name'] ?? '')
                          .toString()
                          .toLowerCase();
                      return code.contains(query) || name.contains(query);
                    }).toList();

                    return Stack(
                      children: [
                        /// LIST
                        ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            return _Row(index: i, item: filtered[i]);
                          },
                        ),

                        if (isLoading)
                          Positioned.fill(
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.6),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primaryColor,
                                ),
                              ),
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
    );
  }
}

class _AddForm extends StatefulWidget {
  const _AddForm();

  @override
  State<_AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<_AddForm> {
  final code = TextEditingController();
  final name = TextEditingController();
  final system = TextEditingController();
  final actual = TextEditingController();

  final codeLink = LayerLink();
  final nameLink = LayerLink();

  final codeFocus = FocusNode();
  final nameFocus = FocusNode();

  OverlayEntry? overlayEntry;

  String activeField = '';

  @override
  void dispose() {
    removeOverlay();
    codeFocus.dispose();
    nameFocus.dispose();
    super.dispose();
  }

  void showOverlay(BuildContext context, OrdersState state, OrdersBloc bloc) {
    removeOverlay();

    final overlay = Overlay.of(context);

    final link = activeField == 'code' ? codeLink : nameLink;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  removeOverlay();
                  codeFocus.unfocus();
                  nameFocus.unfocus();
                },
              ),
            ),

            Positioned(
              width: 400,
              child: CompositedTransformFollower(
                link: link,
                offset: const Offset(0, 55),
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
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

    overlay.insert(overlayEntry!);
  }

  void removeOverlay() {
    overlayEntry?.remove();
    overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<OrdersBloc, OrdersState>(
      listener: (context, state) {
        if (state.mismatchSuggestions.isNotEmpty &&
            (codeFocus.hasFocus || nameFocus.hasFocus)) {
          showOverlay(context, state, context.read<OrdersBloc>());
        } else {
          removeOverlay();
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: CompositedTransformTarget(
                    link: codeLink,
                    child: TextField(
                      focusNode: codeFocus,
                      controller: code,
                      decoration: InputDecoration(
                        labelText: "Item Code",
                        labelStyle: TextStyle(color: AppColors.secondaryColor),
                        filled: true,
                        fillColor: AppColors.backgroundWidget,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.primaryColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.primaryColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.primaryColor),
                        ),
                      ),
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
                    child: TextField(
                      focusNode: nameFocus,
                      controller: name,
                      decoration: InputDecoration(
                        labelText: "Item Name",
                        labelStyle: TextStyle(color: AppColors.secondaryColor),

                        filled: true,
                        fillColor: AppColors.backgroundWidget,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.primaryColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.primaryColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.primaryColor),
                        ),
                      ),
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

            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: system,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: "System Qty",
                      labelStyle: TextStyle(color: AppColors.secondaryColor),

                      filled: true,
                      fillColor: AppColors.backgroundWidget,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primaryColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primaryColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primaryColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: actual,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: "Actual Qty",
                      labelStyle: TextStyle(color: AppColors.secondaryColor),

                      filled: true,
                      fillColor: AppColors.backgroundWidget,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primaryColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primaryColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primaryColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 15),

            BlocListener<OrdersBloc, OrdersState>(
              listenWhen: (prev, curr) =>
                  prev.showMismatchResult != curr.showMismatchResult,
              listener: (context, state) {
                if (state.showMismatchResult == true) {
                  if (state.lastActionSuccess == true) {
                    showTopSnackBar(
                      context,
                      "Added successfully",
                      Colors.green,
                    );
                  } else {
                    showTopSnackBar(
                      context,
                      "Item already exists!",
                      Colors.red,
                    );
                  }

                  context.read<OrdersBloc>().add(OrdersClearMismatchResult());
                }
              },
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, color: AppColors.white),
                label: const Text(
                  "Add Mismatch",
                  style: TextStyle(color: AppColors.white),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.primaryColor,
                  minimumSize: const Size(300, 40),
                ),
                onPressed: () {
                  final systemVal = num.tryParse(system.text) ?? 0;
                  final actualVal = num.tryParse(actual.text) ?? 0;

                  if (code.text.isEmpty || name.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please select item first")),
                    );
                    return;
                  }

                  context.read<OrdersBloc>().add(
                    OrdersAddMismatch({
                      'branch_name': context
                          .read<OrdersBloc>()
                          .state
                          .branchName,
                      'item_code': code.text,
                      'item_name': name.text,
                      'system_stock': systemVal,
                      'actual_stock': actualVal,
                    }),
                  );

                  code.clear();
                  name.clear();
                  system.clear();
                  actual.clear();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showTopSnackBar(BuildContext context, String text, Color color) {
  final overlay = Overlay.of(context);

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      top: 40,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white)),
        ),
      ),
    ),
  );

  overlay.insert(entry);

  Future.delayed(const Duration(seconds: 2), () {
    entry.remove();
  });
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
              context.read<OrdersBloc>().add(OrdersDeleteMismatch(id));
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    },
  );
}

void _showEditDialog(BuildContext context, Map item) {
  final systemController = TextEditingController(
    text: item['system_stock'].toString(),
  );
  final actualController = TextEditingController(
    text: item['actual_stock'].toString(),
  );

  showDialog(
    context: context,
    builder: (_) {
      return AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("Edit Mismatch"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${item['item_name']}"),

            const SizedBox(height: 20),

            TextField(
              controller: systemController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "System Qty",
                labelStyle: TextStyle(color: AppColors.secondaryColor),
                filled: true,
                fillColor: AppColors.backgroundWidget,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: actualController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Actual Qty",
                labelStyle: TextStyle(color: AppColors.secondaryColor),
                filled: true,
                fillColor: AppColors.backgroundWidget,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Cancel",
              style: TextStyle(color: AppColors.secondaryColor),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<OrdersBloc>().add(
                OrdersUpdateMismatch(
                  id: item['id'].toString(),
                  system: num.tryParse(systemController.text) ?? 0,
                  actual: num.tryParse(actualController.text) ?? 0,
                  old: item,
                ),
              );

              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
            ),
            child: const Text("Save", style: TextStyle(color: AppColors.white)),
          ),
        ],
      );
    },
  );
}

class _Row extends StatelessWidget {
  final Map item;
  final int index;

  const _Row({required this.item, required this.index});

  Color _getDiffColor(num diff) {
    if (diff > 0) return Colors.green;
    if (diff < 0) return Colors.red;
    return Colors.grey;
  }

  String _format(num v) {
    if (v % 1 == 0) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final system = (item['system_stock'] ?? 0) as num;
    final actual = (item['actual_stock'] ?? 0) as num;

    final diff = actual - system;

    return Card(
      color: Colors.white,
      elevation: 3,
      shadowColor: AppColors.secondaryColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primaryColor),
      ),
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

            /// ITEM CODE
            Expanded(
              flex: 2,
              child: Text(
                item['item_code'].toString(),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),

            /// ITEM NAME
            Expanded(
              flex: 4,
              child: Text(
                item['item_name'].toString(),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            /// SYSTEM
            Expanded(
              child: Text(
                "System: ${_format(system)}",
                style: const TextStyle(fontSize: 13),
              ),
            ),

            /// ACTUAL
            Expanded(
              child: Text(
                "Actual: ${_format(actual)}",
                style: const TextStyle(fontSize: 13),
              ),
            ),

            /// 🔥 DIFF
            Expanded(
              child: Text(
                "Diff: ${_format(diff)}",
                style: TextStyle(
                  color: _getDiffColor(diff),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),

            const SizedBox(width: 8),

            /// EDIT
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              tooltip: "Edit",
              onPressed: () {
                _showEditDialog(context, item);
              },
            ),

            /// DELETE
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: "Delete",
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
      ),
    );
  }
}
