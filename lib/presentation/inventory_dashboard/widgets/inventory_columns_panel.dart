import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../orders/widgets/orders_table.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';

class InventoryColumnsPanel extends StatelessWidget {
  const InventoryColumnsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: BlocBuilder<InventoryBloc, InventoryState>(
          builder: (context, s) {
            final all = s.columnOrder;
            final visible = s.visibleColumns;

            final filtered = all
                .where((k) => k != 'additional_request')
                .toList();

            return Column(
              children: [
                /// HEADER
                Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          "Columns",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        context.read<InventoryBloc>().add(
                          InventoryResetColumns(),
                        );
                      },
                      icon: const Icon(Icons.restart_alt),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),

                const Divider(),

                /// LIST
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: filtered.length,
                    onReorder: (oldIndex, newIndex) {
                      context.read<InventoryBloc>().add(
                        InventoryReorderColumns(
                          oldIndex: oldIndex,
                          newIndex: newIndex,
                        ),
                      );
                    },
                    itemBuilder: (context, index) {
                      final key = filtered[index];

                      final title =
                          OrdersTable.titles[key] ??
                          OrdersTable.optionalTitles[key] ??
                          key;

                      final isOn = visible.contains(key);

                      return ListTile(
                        key: ValueKey(key),
                        title: Text(title),
                        trailing: Switch(
                          value: isOn,
                          onChanged: (v) {
                            context.read<InventoryBloc>().add(
                              InventorySetColumnVisible(
                                columnKey: key,
                                visible: v,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
