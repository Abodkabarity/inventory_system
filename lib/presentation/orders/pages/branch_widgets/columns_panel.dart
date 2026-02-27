// columns_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/order_bloc/orders_bloc.dart';
import '../../bloc/order_bloc/orders_event.dart';
import '../../bloc/order_bloc/orders_state.dart';
import '../../widgets/orders_table.dart';

class ColumnsPanel extends StatelessWidget {
  const ColumnsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 420,
      child: SafeArea(
        child: BlocBuilder<OrdersBloc, OrdersState>(
          buildWhen: (p, n) =>
              p.visibleColumns != n.visibleColumns ||
              p.columnOrder != n.columnOrder,
          builder: (context, s) {
            final all = s.columnOrder;
            final visible = s.visibleColumns;

            return Column(
              children: [
                _Header(
                  title: 'Columns',
                  subtitle: 'Show/Hide and reorder table columns',
                  onClose: () => Navigator.of(context).maybePop(),
                  onReset: () => context.read<OrdersBloc>().add(
                    const OrdersResetColumnsToDefault(),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                    itemCount: all.length,
                    onReorder: (oldIndex, newIndex) {
                      context.read<OrdersBloc>().add(
                        OrdersReorderColumns(
                          oldIndex: oldIndex,
                          newIndex: newIndex,
                        ),
                      );
                    },
                    itemBuilder: (context, index) {
                      final key = all[index];

                      final title =
                          OrdersTable.titles[key] ??
                          OrdersTable.optionalTitles[key] ??
                          key;

                      final isOn = visible.contains(key);
                      final locked = (key == 'item_code' || key == 'item_name');

                      return _ColumnTile(
                        key: ValueKey(key),
                        title: title.replaceAll('\n', ' '),
                        subtitle: key,
                        enabled: !locked,
                        value: isOn,
                        onChanged: (v) {
                          context.read<OrdersBloc>().add(
                            OrdersSetColumnVisible(columnKey: key, visible: v),
                          );
                        },
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

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final VoidCallback onReset;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reset',
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _ColumnTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ColumnTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6E8F0)),
        ),
        child: ListTile(
          leading: const Icon(Icons.drag_indicator_rounded),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.8),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280)),
          ),
          trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
        ),
      ),
    );
  }
}
