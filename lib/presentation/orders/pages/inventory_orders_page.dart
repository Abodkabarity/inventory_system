/*
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/orders_bloc.dart';
import '../bloc/orders_bloc_factory.dart';
import '../bloc/orders_event.dart';
import '../bloc/orders_state.dart';
import '../widgets/orders_table.dart';
import '../widgets/orders_toolbar.dart';
import '../widgets/toggle_item.dart';

class InventoryOrdersPage extends StatelessWidget {
  final String runDate;

  const InventoryOrdersPage({super.key, required this.runDate});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final b = OrdersBlocFactory.create(
          runDate: runDate,
          branchName: '__ALL__',
        );
        b.add(const OrdersLoadPage(pageIndex: 0, pageSize: 150));
        return b;
      },
      child: const _InventoryOrdersView(),
    );
  }
}

class _InventoryOrdersView extends StatefulWidget {
  const _InventoryOrdersView();

  @override
  State<_InventoryOrdersView> createState() => _InventoryOrdersViewState();
}

class _InventoryOrdersViewState extends State<_InventoryOrdersView> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersBloc, OrdersState>(
      builder: (context, s) {
        final isLoading =
            s.status == OrdersStatus.loading ||
            s.status == OrdersStatus.generating;

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(title: Text('Inventory • ${s.runDate}')),
          endDrawer: ColumnsTogglePanel(
            items: OrdersTable.optionalToggleItems()
                .map((e) => ToggleItem(e.key, e.value))
                .toList(),

            selectedKeys: s.visibleOptionalColumns,
            onToggle: (k, v) => context.read<OrdersBloc>().add(
              OrdersToggleColumn(columnKey: k, visible: v),
            ),
            onReset: () =>
                context.read<OrdersBloc>().add(const OrdersResetColumns()),
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                OrdersToolbar(
                  search: s.search,
                  onSearchChanged: (v) =>
                      context.read<OrdersBloc>().add(OrdersSearchChanged(v)),
                  onOpenColumns: () =>
                      _scaffoldKey.currentState?.openEndDrawer(),
                  onExport: () {},
                  actions: [
                    FilledButton.icon(
                      onPressed: isLoading
                          ? null
                          : () => context.read<OrdersBloc>().add(
                              const OrdersGenerateAll(),
                            ),
                      icon: const Icon(Icons.bolt),
                      label: const Text('Generate All'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (s.status == OrdersStatus.generating)
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: (s.progress / 100.0).clamp(0, 1),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${s.progress.toStringAsFixed(0)}% ${s.progressMessage ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                Row(
                  children: [
                    Text(
                      'Page: ${s.pageIndex + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: (s.pageIndex <= 0 || isLoading)
                          ? null
                          : () => context.read<OrdersBloc>().add(
                              OrdersLoadPage(
                                pageIndex: s.pageIndex - 1,
                                pageSize: s.pageSize,
                              ),
                            ),
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Prev'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: isLoading
                          ? null
                          : () => context.read<OrdersBloc>().add(
                              OrdersLoadPage(
                                pageIndex: s.pageIndex + 1,
                                pageSize: s.pageSize,
                              ),
                            ),
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Next'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (s.status == OrdersStatus.failure && s.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      s.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: OrdersTable(
                    rows: s.rows,
                    isLoading: isLoading,
                    visibleOptionalColumns: s.visibleOptionalColumns,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToggleItem {
  final String key;
  final String title;
  const _ToggleItem(this.key, this.title);
}
*/
