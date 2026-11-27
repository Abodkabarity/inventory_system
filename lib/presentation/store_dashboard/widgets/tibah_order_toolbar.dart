import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/print_service.dart';
import '../../../data/datasources/remote/tibah_order_remote_ds.dart';
import '../../../domain/entities/store_order_item.dart';
import '../../../domain/entities/tibah_order.dart';
import 'tibah_order_window.dart';

class TibahOrderToolbar extends StatefulWidget {
  const TibahOrderToolbar({
    super.key,
    required this.order,
    required this.items,
    required this.loaded,
    required this.onRefresh,
    this.onClose,
  });
  final TibahOrder order;
  final List<StoreOrderItem> items;
  final bool loaded;
  final VoidCallback onRefresh;
  final VoidCallback? onClose;

  @override
  State<TibahOrderToolbar> createState() => _TibahOrderToolbarState();
}

class _TibahOrderToolbarState extends State<TibahOrderToolbar> {
  bool _busy = false;
  String? _error;

  Future<void> _act({bool? isGeneral}) async {
    final order = widget.order;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final remote = TibahOrderRemoteDs(Supabase.instance.client);
      if (isGeneral == null) {
        await remote.complete(order.id);
        widget.onRefresh();
        if (mounted) widget.onClose?.call();
      } else {
        final latest = await remote.current(order.type);
        if (latest?.id != order.id || latest?.isReady != true) {
          throw StateError(
            'This order has changed or finished. Refresh before printing.',
          );
        }
        await PrintService.printOrders(
          branch: order.branch,
          items: widget.items,
          isGeneral: isGeneral,
          tibahOrder: order,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final color = order.type == TibahOrderType.upp
        ? const Color(0xFF6D28D9)
        : const Color(0xFF1E40AF);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${order.type.label.toUpperCase()} ORDER',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TibahOrderWindow(order: order),
          const SizedBox(height: 6),
          if (!order.isReady)
            Text(
              'Preparing ${order.prepared} / ${order.total} products. Waiting for the next order calculation.',
              textAlign: TextAlign.center,
            ),
          if (order.isReady && widget.loaded && widget.items.isEmpty)
            const Text(
              'No Qty is available for preparation in this order.',
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final isGeneral in [false, true])
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                  ),
                  onPressed:
                      _busy ||
                          !order.isReady ||
                          !widget.loaded ||
                          !widget.items.any(
                            (e) =>
                                e.quantity > 0 &&
                                e.classification.toLowerCase().contains(
                                      'general',
                                    ) ==
                                    isGeneral,
                          )
                      ? null
                      : () => _act(isGeneral: isGeneral),
                  icon: const Icon(Icons.print),
                  label: Text('Print ${order.type.printLabel(isGeneral)}'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                onPressed: _busy || !order.isReady || !widget.loaded
                    ? null
                    : () => _act(),
                icon: const Icon(Icons.task_alt),
                label: const Text('Confirm preparation finished'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.black),
                onPressed: _busy ? null : widget.onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFF9F1239))),
        ],
      ),
    );
  }
}
