import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_theme.dart';
import '../../core/scan_utils.dart';
import '../../domain/entities.dart';
import '../bloc/mobile_order_bloc.dart';
import 'scanner_page.dart';

class PickListPage extends StatefulWidget {
  const PickListPage({super.key});

  @override
  State<PickListPage> createState() => _PickListPageState();
}

class _PickListPageState extends State<PickListPage> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            context.read<MobileOrderBloc>().add(BackToCategorySelection());
          },
          icon: const Icon(Icons.arrow_back),
        ),
        title: BlocBuilder<MobileOrderBloc, MobileOrderState>(
          builder: (context, state) {
            return Text('${state.selectedCategory?.label ?? ''} Picking');
          },
        ),
      ),
      body: BlocBuilder<MobileOrderBloc, MobileOrderState>(
        builder: (context, state) {
          final all = state.visibleItems;
          final q = query.text.trim().toLowerCase();
          final rows = q.isEmpty
              ? all
              : all.where((item) {
                  return item.itemCode.toLowerCase().contains(q) ||
                      item.itemName.toLowerCase().contains(q) ||
                      item.barcode.toLowerCase().contains(q);
                }).toList();

          return Column(
            children: [
              _TopProgress(state: state),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: TextField(
                  controller: query,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search item, code, or barcode...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = rows[index];
                    final picked = state.picked[item.itemCode];
                    return _PickItemCard(
                      item: item,
                      picked: picked,
                      index: index + 1,
                      onTap: () => _scanOrEditItem(context, item, picked),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BlocBuilder<MobileOrderBloc, MobileOrderState>(
        builder: (context, state) {
          final busy = state.busyMessage.isNotEmpty;
          final pickedCount = state.visibleItems
              .where((e) => state.picked.containsKey(e.itemCode))
              .length;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: ElevatedButton.icon(
                onPressed: pickedCount > 0 && !busy
                    ? () => context.read<MobileOrderBloc>().add(
                        CategorySubmitted(),
                      )
                    : null,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.cloud_upload_outlined),
                label: Text(
                  busy
                      ? 'Submitting...'
                      : pickedCount > 0
                      ? 'Upload scanned items ($pickedCount)'
                      : 'Scan at least one item',
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _scanOrEditItem(
    BuildContext context,
    MobileOrderItem item,
    PickedItem? picked,
  ) async {
    if (picked != null) {
      final edit = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text('Edit scanned item?'),
            content: Text(
              '${item.itemName}\nCurrent picked qty: ${picked.pickedQty}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.edit),
                label: const Text('Edit quantity'),
              ),
            ],
          );
        },
      );
      if (!context.mounted || edit != true) return;
      final qty = await _askQuantity(
        context,
        item,
        initialQty: picked.pickedQty,
      );
      if (!context.mounted || qty == null) return;
      context.read<MobileOrderBloc>().add(
        PickConfirmed(
          item: item,
          qty: qty,
          scannedBarcode: picked.scannedBarcode,
        ),
      );
      return;
    }

    final scanned = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => ScannerPage(item: item)));
    if (!context.mounted || scanned == null || scanned.trim().isEmpty) return;

    if (!scanMatches(
      scanned: scanned,
      itemCode: item.itemCode,
      barcode: item.barcode,
      validBarcodes: item.validBarcodes,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Different product scanned. Expected ${item.itemCode} / ${item.barcode.isEmpty ? 'valid barcode' : item.barcode}',
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final qty = await _askQuantity(context, item);
    if (!context.mounted || qty == null) return;

    context.read<MobileOrderBloc>().add(
      PickConfirmed(item: item, qty: qty, scannedBarcode: scanned),
    );
  }

  Future<num?> _askQuantity(
    BuildContext context,
    MobileOrderItem item, {
    num? initialQty,
  }) async {
    final controller = TextEditingController(
      text: (initialQty ?? item.expectedQty).toString(),
    );
    return showDialog<num>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Confirm quantity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.itemName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text('Expected qty: ${item.expectedQty}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Picked quantity',
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = num.tryParse(controller.text.trim());
                Navigator.pop(context, value);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }
}

class _TopProgress extends StatelessWidget {
  final MobileOrderState state;

  const _TopProgress({required this.state});

  @override
  Widget build(BuildContext context) {
    final total = state.visibleItems.length;
    final done = state.visibleItems
        .where((e) => state.picked.containsKey(e.itemCode))
        .length;
    final progress = total == 0 ? 0.0 : done / total;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.blue, AppTheme.deepBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.qr_code_scanner,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${state.selectedBranch} - ${state.selectedCategory?.label}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(20),
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  '$done of $total confirmed',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickItemCard extends StatelessWidget {
  final MobileOrderItem item;
  final PickedItem? picked;
  final int index;
  final VoidCallback onTap;

  const _PickItemCard({
    required this.item,
    required this.picked,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final confirmed = picked != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: confirmed ? const Color(0xffe8f8ef) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: confirmed ? AppTheme.mint : const Color(0xffd6e4f2),
            width: confirmed ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: confirmed
                    ? AppTheme.mint
                    : AppTheme.blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: confirmed
                    ? const Icon(Icons.check, color: Colors.white)
                    : Text(
                        '$index',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${item.itemCode} - ${item.barcode.isEmpty ? 'No barcode' : item.barcode}',
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              children: [
                const Text(
                  'QTY',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
                Text(
                  '${item.expectedQty}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
