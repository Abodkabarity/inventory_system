import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';

class PurchaseShortagePage extends StatefulWidget {
  final String runDate;

  const PurchaseShortagePage({super.key, required this.runDate});

  @override
  State<PurchaseShortagePage> createState() => _PurchaseShortagePageState();
}

class _PurchaseShortagePageState extends State<PurchaseShortagePage> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant PurchaseShortagePage oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    context.read<InventoryBloc>().add(LoadPurchaseShortage(widget.runDate));
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((row) {
      return _s(row['item_code']).toLowerCase().contains(q) ||
          _s(row['item_name']).toLowerCase().contains(q) ||
          _s(row['category']).toLowerCase().contains(q) ||
          _s(row['supplier']).toLowerCase().contains(q) ||
          _s(row['assortment_items']).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (p, c) =>
          p.isPurchaseShortageLoading != c.isPurchaseShortageLoading ||
          p.purchaseShortageRows != c.purchaseShortageRows ||
          p.purchaseShortageError != c.purchaseShortageError,
      builder: (context, state) {
        final rows = _filter(state.purchaseShortageRows);
        final totalShortage = rows.fold<num>(
          0,
          (sum, row) => sum + _n(row['shortage']),
        );
        final totalBranchStock = rows.fold<num>(
          0,
          (sum, row) => sum + _n(row['branches_stock']),
        );
        final tmaCount = rows
            .where((row) => _s(row['assortment_items']).toUpperCase() == 'TMA')
            .length;

        return Container(
          color: const Color(0xffF4F7FB),
          child: Column(
            children: [
              _Header(
                runDate: widget.runDate,
                isLoading: state.isPurchaseShortageLoading,
                rowsCount: rows.length,
                onRefresh: _load,
                onExport: state.purchaseShortageRows.isEmpty
                    ? null
                    : () => context.read<InventoryBloc>().add(
                        ExportPurchaseShortage(widget.runDate),
                      ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
                  children: [
                    if (state.purchaseShortageError.isNotEmpty)
                      _ErrorBanner(message: state.purchaseShortageError),
                    _SummaryRow(
                      rowsCount: rows.length,
                      totalShortage: totalShortage,
                      totalBranchStock: totalBranchStock,
                      tmaCount: tmaCount,
                    ),
                    const SizedBox(height: 18),
                    _SearchBar(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _search = value),
                    ),
                    const SizedBox(height: 14),
                    _TableCard(
                      rows: rows,
                      isLoading: state.isPurchaseShortageLoading,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String runDate;
  final bool isLoading;
  final int rowsCount;
  final VoidCallback onRefresh;
  final VoidCallback? onExport;

  const _Header({
    required this.runDate,
    required this.isLoading,
    required this.rowsCount,
    required this.onRefresh,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(36, 28, 28, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff0EA5E9), Color(0xff2563EB)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .24)),
            ),
            child: const Icon(
              Icons.production_quantity_limits_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Purchase Shortage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Calculate shortage from daily order data. Run date: $runDate',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _HeaderMetric(label: 'Rows', value: '$rowsCount'),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: isLoading ? null : onRefresh,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(isLoading ? 'Calculating' : 'Calculate Shortage'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff047857),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Export'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xff2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .20)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .78),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int rowsCount;
  final num totalShortage;
  final num totalBranchStock;
  final int tmaCount;

  const _SummaryRow({
    required this.rowsCount,
    required this.totalShortage,
    required this.totalBranchStock,
    required this.tmaCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SummaryCard(
          title: 'Shortage Items',
          value: '$rowsCount',
          icon: Icons.inventory_2_outlined,
          color: const Color(0xff2563EB),
        ),
        const SizedBox(width: 14),
        _SummaryCard(
          title: 'Total Shortage',
          value: _fmt(totalShortage),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xffEF4444),
        ),
        const SizedBox(width: 14),
        _SummaryCard(
          title: 'Branches Stock',
          value: _fmt(totalBranchStock),
          icon: Icons.storefront_rounded,
          color: const Color(0xff10B981),
        ),
        const SizedBox(width: 14),
        _SummaryCard(
          title: 'TMA Items',
          value: '$tmaCount',
          icon: Icons.medication_rounded,
          color: const Color(0xffF97316),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .035),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xff0F172A),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText:
            'Search item code, item name, category, supplier, assortment...',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xffD8E5F3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xffD8E5F3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xff0EA5E9), width: 1.5),
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool isLoading;

  const _TableCard({required this.rows, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffD8E5F3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(Icons.table_chart_rounded, color: Color(0xff0EA5E9)),
                const SizedBox(width: 10),
                const Text(
                  'TotalShortage',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xff0F172A),
                  ),
                ),
                const Spacer(),
                Text(
                  '${rows.length} rows',
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Text(
                  'Press Calculate Shortage to generate the report.',
                  style: TextStyle(color: Color(0xff64748B)),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  Color(0xff002060),
                ),
                headingTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
                dataRowMinHeight: 48,
                dataRowMaxHeight: 58,
                columnSpacing: 28,
                border: TableBorder.all(color: const Color(0xffCBD5E1)),
                columns: const [
                  DataColumn(label: Text('Item Code')),
                  DataColumn(label: Text('Item Name')),
                  DataColumn(label: Text('Branches Stock')),
                  DataColumn(label: Text('Category')),
                  DataColumn(label: Text('Supplier')),
                  DataColumn(label: Text('Store Stock')),
                  DataColumn(label: Text('Shortage')),
                  DataColumn(label: Text('UPP Shortage')),
                  DataColumn(label: Text('Assortment Items')),
                ],
                rows: rows.map((row) {
                  return DataRow(
                    cells: [
                      DataCell(_cell(_s(row['item_code']))),
                      DataCell(_wideCell(_s(row['item_name']), 360)),
                      DataCell(_cell(_fmt(row['branches_stock']))),
                      DataCell(_wideCell(_s(row['category']), 170)),
                      DataCell(_wideCell(_s(row['supplier']), 210)),
                      DataCell(_cell(_fmt(row['store_stock']))),
                      DataCell(
                        Text(
                          _fmt(row['shortage']),
                          style: const TextStyle(
                            color: Color(0xffDC2626),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      DataCell(_cell(_s(row['upp_shortage']))),
                      DataCell(_wideCell(_s(row['assortment_items']), 260)),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xffDC2626)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xff991B1B)),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _cell(String text) {
  return Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(fontWeight: FontWeight.w700),
  );
}

Widget _wideCell(String text, double width) {
  return SizedBox(
    width: width,
    child: Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

String _s(dynamic value) => (value ?? '').toString();

num _n(dynamic value) {
  if (value is num) return value;
  return num.tryParse(_s(value)) ?? 0;
}

String _fmt(dynamic value) {
  final n = _n(value);
  if (n % 1 == 0) return n.toInt().toString();
  return n.toStringAsFixed(2);
}
