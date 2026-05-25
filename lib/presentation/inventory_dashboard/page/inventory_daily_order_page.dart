import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../orders/widgets/orders_grid_controller.dart';
import '../../orders/widgets/orders_table.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/inventory_columns_panel.dart';
import '../widgets/inventory_orders_table.dart';

class InventoryDailyOrderPage extends StatefulWidget {
  final String runDate;

  const InventoryDailyOrderPage({super.key, required this.runDate});

  @override
  State<InventoryDailyOrderPage> createState() =>
      _InventoryDailyOrderPageState();
}

class _InventoryDailyOrderPageState extends State<InventoryDailyOrderPage> {
  final OrdersGridController controller = OrdersGridController();

  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  @override
  void initState() {
    super.initState();

    context.read<InventoryBloc>().add(LoadInventoryOrders(widget.runDate));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        final filteredRows = state.allOrders.where((e) {
          final q = searchQuery.toLowerCase();

          return e.itemName.toLowerCase().contains(q) ||
              e.itemCode.toLowerCase().contains(q) ||
              e.branch.toLowerCase().contains(q);
        }).toList();

        final columns = state.columnOrder.isEmpty
            ? OrdersTable.allColumns
            : state.columnOrder;

        final visible = state.visibleColumns.isEmpty
            ? OrdersTable.allColumns
            : state.visibleColumns;

        final finalColumns = columns
            .where((c) => visible.contains(c) && c != 'additional_request')
            .toList();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Column(
                children: [
                  /// 🔥 SEARCH + COLUMNS BUTTON
                  Row(
                    children: [
                      /// 🔍 SEARCH
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: "Search item / code / branch...",
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (v) {
                            context.read<InventoryBloc>().add(
                              SearchInventoryOrders(v),
                            );
                          },
                        ),
                      ),

                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () {
                          context.read<InventoryBloc>().add(
                            ExportInventoryOrders(
                              runDate: widget.runDate,
                              visibleColumns: finalColumns,
                            ),
                          );
                        },
                        icon: const Icon(Icons.download),
                        label: const Text("Export"),
                      ),
                      const SizedBox(width: 10),

                      /// 🧩 COLUMNS BUTTON
                      ElevatedButton.icon(
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (bottomSheetContext) {
                              final bloc = context.read<InventoryBloc>();

                              return BlocProvider.value(
                                value: bloc,
                                child: const InventoryColumnsPanel(),
                              );
                            },
                          );
                        },
                        icon: const Icon(Icons.view_column),
                        label: const Text("Columns"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  /// 📊 TABLE
                  /// 📊 TABLE
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: InventoryOrdersTable(
                            rows: filteredRows,

                            isLoading: state.isOrdersLoading,

                            orderedColumns: finalColumns,

                            columnWidths: {},

                            onColumnResized: (_, __) {},
                          ),
                        ),

                        /// =====================================
                        /// PAGINATION
                        /// =====================================
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 20,
                          ),

                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),

                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,

                            children: [
                              /// PREVIOUS
                              ElevatedButton.icon(
                                onPressed: state.currentPage == 0
                                    ? null
                                    : () {
                                        context.read<InventoryBloc>().add(
                                          LoadOrdersPage(
                                            runDate: widget.runDate,

                                            page: state.currentOrdersPage - 1,
                                          ),
                                        );
                                      },

                                icon: const Icon(Icons.arrow_back),

                                label: const Text("Previous"),
                              ),

                              const SizedBox(width: 25),

                              /// PAGE NUMBER
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),

                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,

                                  borderRadius: BorderRadius.circular(12),
                                ),

                                child: Text(
                                  "Page ${state.currentOrdersPage + 1}",

                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 25),

                              /// NEXT
                              ElevatedButton.icon(
                                onPressed: !state.hasMorePages
                                    ? null
                                    : () {
                                        context.read<InventoryBloc>().add(
                                          LoadOrdersPage(
                                            runDate: widget.runDate,

                                            page: state.currentOrdersPage + 1,
                                          ),
                                        );
                                      },

                                icon: const Icon(Icons.arrow_forward),

                                label: const Text("Next"),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (state.isExporting)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.25),
                    child: Center(
                      child: Container(
                        width: 320,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 70,
                              height: 70,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    strokeWidth: 6,
                                    value: state.importProgress,
                                  ),

                                  Text(
                                    "${(state.importProgress * 100).toStringAsFixed(0)}%",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            Text(
                              state.exportMessage ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
