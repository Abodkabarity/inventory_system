import '../../../domain/entities/daily_order_row.dart';
import '../bloc/order_bloc/orders_state.dart';

class BranchStats {
  final int totalProducts;
  final num sumFinalReorder;
  final int essential;
  final int non;

  const BranchStats({
    required this.totalProducts,
    required this.sumFinalReorder,
    required this.essential,
    required this.non,
  });
}

class BranchOrdersSelectors {
  static List<String> orderedVisibleColumns(OrdersState s) {
    final order = s.columnOrder;
    final visible = s.visibleColumns;

    final out = <String>[];
    if (!out.contains('row_no')) out.add('row_no');

    for (final k in order) {
      if (visible.contains(k)) out.add(k);
    }

    if (!out.contains('item_code')) out.insert(1, 'item_code');
    if (!out.contains('item_name')) out.insert(2, 'item_name');

    return out;
  }

  static num extractNumeric(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 0;

    final direct = num.tryParse(s.replaceAll(',', ''));
    if (direct != null) return direct;

    final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    if (m == null) return 0;
    return num.tryParse(m.group(0) ?? '') ?? 0;
  }

  static BranchStats calcStats(List<DailyOrderRow> rows) {
    int essential = 0;
    int non = 0;
    num sumFinal = 0;

    for (final row in rows) {
      sumFinal += extractNumeric(row.finalReorderQtyStoreStockGt0);

      final f = (row.branchFormulary ?? '').trim().toUpperCase();
      if (f == 'ESSENTIAL') essential++;
      if (f == 'NON') non++;
    }

    return BranchStats(
      totalProducts: rows.length,
      sumFinalReorder: sumFinal,
      essential: essential,
      non: non,
    );
  }

  static List<String> extractCategories(List<DailyOrderRow> rows) {
    final set = <String>{};
    for (final r in rows) {
      final cat = (r.category ?? '').trim();
      if (cat.isNotEmpty) set.add(cat);
    }
    final list = set.toList()..sort();
    return ['ALL', ...list];
  }
}
