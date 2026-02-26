import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/csv_exporter_web.dart';
import '../bloc/branch_bloc.dart';
import '../bloc/branch_rules_bloc.dart';
import '../bloc/branch_rules_bloc_factory.dart';
import '../bloc/branch_rules_event.dart';
import '../bloc/branch_rules_state.dart';
import '../bloc/catalog_bloc.dart';
import '../bloc/catalog_event.dart';
import '../bloc/catalog_state.dart';
import '../bloc/demand_bloc/ordering_calc_bloc.dart';
import '../bloc/demand_bloc/ordering_calc_event.dart';
import '../bloc/demand_bloc/ordering_calc_state.dart';
import '../bloc/demand_bloc/ordering_calcbloc_factory.dart';
import '../bloc/stock_bloc/stock_bloc.dart';
import '../bloc/stock_bloc/stock_bloc_factory.dart';
import '../bloc/stock_bloc/stock_event.dart';
import '../bloc/stock_bloc/stock_state.dart';
import '../widgets/items_table.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => CatalogBloc()),
        BlocProvider(create: (_) => BranchRulesBlocFactory.create()),
        BlocProvider(create: (_) => StockBlocFactory.create()),
        BlocProvider(create: (_) => OrderingCalcBlocFactory.create()),
        BlocProvider(create: (_) => BranchBloc()..add(const LoadMyBranch())),
      ],
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  String? _loadedBranchRulesFor;

  final String _storeName = 'STORE';

  int _lastCalcKey = 0;

  String _normCode(String v) {
    var s = v.trim().replaceAll(' ', '');
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  void _loadRulesIfNeeded(BuildContext context) {
    final branchState = context.read<BranchBloc>().state;
    final b = branchState.branchName?.trim();

    if (b == null || b.isEmpty) return;
    if (_loadedBranchRulesFor == b) return;

    _loadedBranchRulesFor = b;

    context.read<BranchRulesBloc>().add(LoadBranchRules(b));

    context.read<StockBloc>().add(
      LoadStockMaps(branchName: b, storeName: _storeName),
    );
  }

  void _onCreateOrderPressed(BuildContext context) {
    _loadRulesIfNeeded(context);
    context.read<CatalogBloc>().add(LoadItemReport());
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;

    final parts = s.split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  int _daysSince(DateTime? date) {
    if (date == null) return 999999;
    final now = DateTime.now();
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(date.year, date.month, date.day);
    return a.difference(b).inDays;
  }

  String _calcMaxAdjValue(Map<String, dynamic> maxRow) {
    final type = (maxRow['adjustment_type'] ?? '')
        .toString()
        .trim()
        .toUpperCase();

    final updateDate = _parseDate(maxRow['update_date']);
    final days = _daysSince(updateDate);

    if (type == 'DECREASE' && days >= 45) return '';
    if (type == 'INCREASE' && days >= 15) return '';

    final v = maxRow['max_adjustment_30d'];
    return v == null ? '' : v.toString();
  }

  int _calcRowsKey({
    required String branchName,
    required List<Map<String, dynamic>> rows,
  }) {
    if (rows.isEmpty) return branchName.hashCode;

    final first = _normCode((rows.first['item_code'] ?? '').toString());
    final last = _normCode((rows.last['item_code'] ?? '').toString());

    final len = rows.length;
    final a = first.hashCode;
    final b = last.hashCode;
    final c = branchName.hashCode;

    return len ^ a ^ (b << 1) ^ (c << 2);
  }

  void _triggerCalcIfReady({
    required BuildContext context,
    required String? branchName,
    required CatalogState catalog,
    required BranchRulesState rules,
    required StockState stock,
    required BranchState branchState,
    required List<Map<String, dynamic>> mergedRows,
  }) {
    if (branchName == null || branchName.trim().isEmpty) return;
    if (mergedRows.isEmpty) return;

    final isLoading =
        catalog.isLoading ||
        rules.status == BranchRulesStatus.loading ||
        branchState.status == BranchStatus.loading ||
        stock.status == StockStatus.loading;

    if (isLoading) return;

    if (rules.status == BranchRulesStatus.loading) return;
    if (rules.status == BranchRulesStatus.failure) return;

    if (stock.status == StockStatus.loading) return;
    if (stock.status == StockStatus.failure) return;

    final key = _calcRowsKey(branchName: branchName, rows: mergedRows);
    if (key == _lastCalcKey) return;

    _lastCalcKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrderingCalcBloc>().add(
        CalculateOrderingColumns(mergedRows),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CatalogBloc, CatalogState>(
      builder: (context, state) {
        final branchState = context.watch<BranchBloc>().state;
        final branchName = branchState.branchName?.trim();

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    onSearch: (v) =>
                        context.read<CatalogBloc>().add(SearchChanged(v)),
                    onExport: () {
                      final calc = context.read<OrderingCalcBloc>().state;
                      final catalog = context.read<CatalogBloc>().state;

                      final rows = (calc.status == OrderingCalcStatus.success)
                          ? calc.rows
                          : catalog.viewRows;

                      if (rows.isEmpty) return;

                      CsvExporterWeb.downloadCsv(
                        rows: rows,
                        columns: ItemsTable.visibleColumns,
                        fileName: 'orders_export.csv',
                      );
                    },
                  ),

                  const SizedBox(height: 10),
                  if (branchState.status == BranchStatus.loading) ...[
                    const Text(
                      'Loading branch...',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ] else if (branchState.status == BranchStatus.failure) ...[
                    Text(
                      'Branch error: ${branchState.error}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Branch: ${branchName ?? "NULL"}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                  const SizedBox(height: 16),

                  BlocBuilder<BranchRulesBloc, BranchRulesState>(
                    builder: (context, rules) {
                      final inOrder = state.viewRows.where((r) {
                        final v = (r['final_qty'] ?? '').toString().trim();
                        return v.isNotEmpty;
                      }).length;

                      int essential = 0;
                      int nonEssential = 0;

                      for (final r in state.viewRows) {
                        final finalQty = (r['final_qty'] ?? '')
                            .toString()
                            .trim();
                        if (finalQty.isEmpty) continue;

                        final code = _normCode(
                          (r['item_code'] ?? '').toString(),
                        );
                        final type =
                            rules.formularyTypeByItemCode[code] ?? 'NON';

                        if (type == 'ESSENTIAL') {
                          essential++;
                        } else {
                          nonEssential++;
                        }
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              title: 'Products in Order',
                              value: '$inOrder',
                              subtitle: 'Items currently added',
                              icon: Icons.inventory_2_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              title: 'Essential',
                              value: '$essential',
                              subtitle: 'ESSENTIAL items',
                              icon: Icons.star_border,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              title: 'Non-Essential',
                              value: '$nonEssential',
                              subtitle: 'NON items',
                              icon: Icons.layers_outlined,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _TableTitle(),
                          const SizedBox(height: 10),
                          if (state.isLoading) ...[
                            _ProgressBar(
                              progress: state.progress,
                              loaded: state.loaded,
                              total: state.total,
                            ),
                            const SizedBox(height: 10),
                          ],
                          Expanded(
                            child:
                                BlocBuilder<BranchRulesBloc, BranchRulesState>(
                                  builder: (context, rules) {
                                    return BlocBuilder<StockBloc, StockState>(
                                      builder: (context, stock) {
                                        final mergedRules = _mergeRulesIntoRows(
                                          rows: state.viewRows,
                                          formularyTypeByItemCode:
                                              rules.formularyTypeByItemCode,
                                          assortmentByItemCode:
                                              rules.assortmentByItemCode,
                                          tmaByItemCode: rules.tmaByItemCode,
                                          maxAdjByItemCode:
                                              rules.maxAdjByItemCode,
                                          demand30ByItemCode:
                                              rules.demand30ByItemCode,
                                        );

                                        final mergedRows = _mergeStockIntoRows(
                                          rows: mergedRules,
                                          storeStockByItemCode:
                                              stock.storeStockByItemCode,
                                          mismatchDiffByItemCode:
                                              stock.mismatchDiffByItemCode,
                                          pendingByItemCode:
                                              stock.pendingByItemCode,
                                          branchStockFinalByItemCode:
                                              stock.branchStockFinalByItemCode,
                                        );

                                        _triggerCalcIfReady(
                                          context: context,
                                          branchName: branchName,
                                          catalog: state,
                                          rules: rules,
                                          stock: stock,
                                          branchState: branchState,
                                          mergedRows: mergedRows,
                                        );

                                        return BlocBuilder<
                                          OrderingCalcBloc,
                                          OrderingCalcState
                                        >(
                                          builder: (context, calc) {
                                            final rowsForTable =
                                                calc.status ==
                                                    OrderingCalcStatus.success
                                                ? calc.rows
                                                : mergedRows;

                                            return ItemsTable(
                                              rows: rowsForTable,
                                              isLoading:
                                                  state.isLoading ||
                                                  rules.status ==
                                                      BranchRulesStatus
                                                          .loading ||
                                                  branchState.status ==
                                                      BranchStatus.loading ||
                                                  stock.status ==
                                                      StockStatus.loading ||
                                                  calc.status ==
                                                      OrderingCalcStatus
                                                          .calculating,
                                              onCreateOrder: () =>
                                                  _onCreateOrderPressed(
                                                    context,
                                                  ),
                                              onEditQty: (index, qty, reason) {
                                                context.read<CatalogBloc>().add(
                                                  UpdateRowField(
                                                    index: index,
                                                    field: 'final_qty',
                                                    value: qty,
                                                  ),
                                                );
                                                context.read<CatalogBloc>().add(
                                                  UpdateRowField(
                                                    index: index,
                                                    field: 'reason',
                                                    value: reason,
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                          ),
                          if (rulesErrorText(context, state) != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              rulesErrorText(context, state)!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? rulesErrorText(BuildContext context, CatalogState state) {
    final rules = context.watch<BranchRulesBloc>().state;
    final stock = context.watch<StockBloc>().state;
    final calc = context.watch<OrderingCalcBloc>().state;

    if (state.error != null) return state.error;
    if (rules.status == BranchRulesStatus.failure) return rules.error;
    if (stock.status == StockStatus.failure) return stock.error;
    if (calc.status == OrderingCalcStatus.failure) return calc.error;
    return null;
  }

  List<Map<String, dynamic>> _mergeRulesIntoRows({
    required List<Map<String, dynamic>> rows,
    required Map<String, String> formularyTypeByItemCode,
    required Map<String, Map<String, dynamic>> assortmentByItemCode,
    required Map<String, Map<String, dynamic>> tmaByItemCode,
    required Map<String, Map<String, dynamic>> maxAdjByItemCode,
    required Map<String, num> demand30ByItemCode,
  }) {
    if (rows.isEmpty) return rows;

    num _n(dynamic v) {
      if (v == null) return 0;
      final s = v.toString().trim();
      if (s.isEmpty) return 0;
      final x = num.tryParse(s.replaceAll(',', ''));
      return x ?? 0;
    }

    int _minUnitFromRow(Map<String, dynamic> r) {
      // item_minimum_order_unit عندك أحياناً يكون موجود بهذا الاسم
      final a = _n(r['item_minimum_order_unit']);
      final b = _n(r['min_order_unit']);
      final c = _n(r['min_order_unit'] ?? r['item_minimum_order_unit']);

      final raw = a > 0 ? a : (b > 0 ? b : c);
      final v = raw <= 0 ? 1 : raw;
      return v.round();
    }

    int _ceilToMultiple(num qty, int unit) {
      if (unit <= 0) unit = 1;
      if (qty <= 0) return 0;
      final q = qty.toDouble();
      final u = unit.toDouble();
      final m = (q / u).ceil();
      return (m * unit).toInt();
    }

    return rows.map((r) {
      final code = _normCode((r['item_code'] ?? '').toString());

      final formulary = formularyTypeByItemCode[code] ?? 'NON';
      final assortment = assortmentByItemCode[code];
      final tma = tmaByItemCode[code];

      final maxRow = maxAdjByItemCode[code];
      final maxAdjValue = maxRow == null ? '' : _calcMaxAdjValue(maxRow);

      final demand30 = demand30ByItemCode[code] ?? 0;
      final demand30Text = demand30.toString();

      final minUnit = _minUnitFromRow(r);

      num baseQtyRaw;
      if (assortment != null) {
        baseQtyRaw = _n(assortment['assortment_qty']);
        if (baseQtyRaw < 0) baseQtyRaw = 0;
      } else {
        if (formulary == 'NON') {
          baseQtyRaw = 0;
        } else {
          baseQtyRaw = 1 * minUnit;
        }
      }

      final baseStockInt = _ceilToMultiple(baseQtyRaw, minUnit);

      return {
        ...r,

        'item_minimum_order_unit': minUnit.toString(),

        'branch_formulary': formulary,
        'max_adjustment_30d': maxAdjValue,
        'qty_30_days_from_last_45d': demand30Text,

        'assortment_qty_base_stock': baseStockInt.toString(),

        if (assortment != null) ...{
          'assortment_by':
              assortment['assortment_by'] ?? r['assortment_by'] ?? '',
          'assortment_start':
              assortment['assortment_start'] ?? r['assortment_start'] ?? '',
          'assortment_end':
              assortment['assortment_end'] ?? r['assortment_end'] ?? '',
          'reason': assortment['reason'] ?? r['reason'] ?? '',
        },

        if (tma != null) ...{
          'tma_qty': tma['final_qty_to_keep'] ?? r['tma_qty'] ?? '',
          'tma_start': tma['start_date'] ?? r['tma_start'] ?? '',
          'tma_end': tma['end_date'] ?? r['tma_end'] ?? '',
        },
      };
    }).toList();
  }

  List<Map<String, dynamic>> _mergeStockIntoRows({
    required List<Map<String, dynamic>> rows,
    required Map<String, num> storeStockByItemCode,
    required Map<String, num> mismatchDiffByItemCode,
    required Map<String, num> pendingByItemCode,
    required Map<String, num> branchStockFinalByItemCode,
  }) {
    if (rows.isEmpty) return rows;

    return rows.map((r) {
      final code = _normCode((r['item_code'] ?? '').toString());

      final storeStock = storeStockByItemCode[code] ?? 0;
      final mismatch = mismatchDiffByItemCode[code] ?? 0;
      final pending = pendingByItemCode[code] ?? 0;
      final branchStockFinal = branchStockFinalByItemCode[code] ?? 0;

      return {
        ...r,
        'store_stock': storeStock.toString(),
        'mismatch_stock': mismatch.toString(),
        'pending_stock_received': pending.toString(),
        'branch_stock': branchStockFinal.toString(),
      };
    }).toList();
  }
}

class _Header extends StatelessWidget {
  final ValueChanged<String> onSearch;
  final VoidCallback onExport;

  const _Header({required this.onSearch, required this.onExport});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Smart Dashboard',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Home • Orders overview & main table',
                style: TextStyle(fontSize: 13, color: AppColors.subText),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 360,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search item / code / barcode',
              prefixIcon: Icon(Icons.search),
              filled: true,
              fillColor: AppColors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide(
                  color: AppColors.secondaryColor,
                  width: 1.4,
                ),
              ),
            ),
            onChanged: onSearch,
          ),
        ),
        const SizedBox(width: 12),

        // ✅ بدل Add New -> Export CSV (يفتح Excel)
        FilledButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.download),
          label: const Text('Export Excel'),
        ),
      ],
    );
  }
}

class _TableTitle extends StatelessWidget {
  const _TableTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.table_rows_outlined, color: AppColors.primaryColor),
        SizedBox(width: 8),
        Text(
          'Main Table',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final int loaded;
  final int total;

  const _ProgressBar({
    required this.progress,
    required this.loaded,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.blueSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: AppColors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$percent%  ($loaded / $total)',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.blueSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.subText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
