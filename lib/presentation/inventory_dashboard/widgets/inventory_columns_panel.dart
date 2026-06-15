import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../orders/bloc/order_bloc/orders_state.dart';
import '../../orders/widgets/orders_table.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';

class InventoryColumnsPanel extends StatefulWidget {
  const InventoryColumnsPanel({super.key});

  @override
  State<InventoryColumnsPanel> createState() => _InventoryColumnsPanelState();
}

class _InventoryColumnsPanelState extends State<InventoryColumnsPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 420.w,
      child: SafeArea(
        child: BlocBuilder<InventoryBloc, InventoryState>(
          buildWhen: (p, n) =>
              p.visibleColumns != n.visibleColumns ||
              p.columnOrder != n.columnOrder,
          builder: (context, s) {
            final all = s.columnOrder.isEmpty
                ? OrdersState.defaultColumnOrder
                : s.columnOrder;
            final visible = s.visibleColumns.isEmpty
                ? OrdersState.defaultVisibleInTable.toSet()
                : s.visibleColumns.toSet();

            final filtered = all.where((k) => k != 'additional_request').where((
              k,
            ) {
              final title =
                  OrdersTable.titles[k] ?? OrdersTable.optionalTitles[k] ?? k;
              final q = _query.trim().toLowerCase();
              if (q.isEmpty) return true;
              return k.toLowerCase().contains(q) ||
                  title.replaceAll('\n', ' ').toLowerCase().contains(q);
            }).toList();

            return Column(
              children: [
                _Header(
                  title: 'Columns',
                  subtitle: 'Show/Hide and reorder table columns',
                  onClose: () => Navigator.of(context).maybePop(),
                  onReset: () {
                    context.read<InventoryBloc>().add(InventoryResetColumns());
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    onChanged: (v) {
                      setState(() {
                        _query = v;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search columns...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primaryColor),
                      ),
                    ),
                  ),
                ),

                /// LIST
                Expanded(
                  child: _query.trim().isNotEmpty
                      ? ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            return _buildTile(
                              context,
                              filtered[index],
                              visible,
                            );
                          },
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                          itemCount: filtered.length,
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) {
                              newIndex -= 1;
                            }

                            context.read<InventoryBloc>().add(
                              InventoryReorderColumns(
                                oldIndex: oldIndex,
                                newIndex: newIndex,
                              ),
                            );
                          },
                          itemBuilder: (context, index) {
                            return _buildTile(
                              context,
                              filtered[index],
                              visible,
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

  Widget _buildTile(BuildContext context, String key, Set<String> visible) {
    final title =
        OrdersTable.titles[key] ?? OrdersTable.optionalTitles[key] ?? key;
    final locked =
        (key == 'branch' || key == 'item_code' || key == 'item_name');
    final isOn = locked || visible.contains(key);

    return _ColumnTile(
      key: ValueKey(key),
      title: title.replaceAll('\n', ' '),
      subtitle: key,
      enabled: !locked,
      value: isOn,
      onChanged: (v) {
        context.read<InventoryBloc>().add(
          InventorySetColumnVisible(columnKey: key, visible: v),
        );
      },
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
          trailing: Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: AppColors.primaryColor,
            inactiveThumbColor: AppColors.secondaryColor,
          ),
        ),
      ),
    );
  }
}
