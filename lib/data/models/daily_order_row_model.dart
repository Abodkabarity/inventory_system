import '../../domain/entities/daily_order_row.dart';

class DailyOrderRowModel extends DailyOrderRow {
  const DailyOrderRowModel({
    required super.branch,
    required super.itemCode,
    required super.itemName,
    required super.branchStock,
    required super.mismatchStock,
    required super.storeStock,
    required super.pendingStockReceived,
    required super.extraQtyMoreThanMonth,
    required super.maxAdjustment30d,
    required super.demandFor30Days,
    required super.finalReorderQtyStoreStockGt0,
    required super.qty30DaysFromLast45d,

    // ✅ ADDED
    required super.reorderQtyNum,

    required super.totalReorderAllBranches,
    super.branchFormulary,
    super.assortmentQtyBaseStock,
    super.assortmentBy,
    super.itemPurchaseType,
    super.category,
    super.isUpp,
    super.uppThiqa,
    super.uppBasic,
    super.minOrderUnit,
    super.subCategory,
    super.company,
    super.supplier,
    super.barcode,
  });

  static String _s(dynamic v) => (v ?? '').toString();

  static num _n(dynamic v) {
    if (v == null) return 0;
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    return num.tryParse(s.replaceAll(',', '')) ?? 0;
  }

  static int _i(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    return int.tryParse(s.replaceAll(',', '')) ?? 0;
  }

  static bool? _b(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return null;
  }

  factory DailyOrderRowModel.fromMap(Map<String, dynamic> m) {
    return DailyOrderRowModel(
      branch: _s(m['branch']).trim(),
      itemCode: _s(m['item_code']).trim(),
      itemName: _s(m['item_name']).trim(),

      branchStock: _n(m['branch_stock']),
      mismatchStock: _n(m['mismatch_stock']),
      storeStock: _n(m['store_stock']),
      pendingStockReceived: _n(m['pending_stock_received']),

      extraQtyMoreThanMonth: _n(m['extra_qty_more_than_month']),
      maxAdjustment30d: _n(m['max_adjustment_30d']),
      demandFor30Days: _n(m['demand_for_30_days']),

      finalReorderQtyStoreStockGt0: _s(
        m['final_reorder_qty_store_stock_gt_0'],
      ).trim(),
      qty30DaysFromLast45d: _n(m['qty_30_days_from_last_45d']),

      // ✅ ADDED
      reorderQtyNum: _n(m['reorder_qty_num']),

      // keep if you still have it in view
      totalReorderAllBranches: _i(m['total_reorder_all_branches']),

      branchFormulary: _s(m['branch_formulary']).trim().isEmpty
          ? null
          : _s(m['branch_formulary']).trim(),

      assortmentQtyBaseStock: _s(m['assortment_qty_base_stock']).trim().isEmpty
          ? null
          : _s(m['assortment_qty_base_stock']).trim(),

      assortmentBy: _s(m['assortment_by']).trim().isEmpty
          ? null
          : _s(m['assortment_by']).trim(),

      itemPurchaseType: _s(m['item_purchase_type']).trim().isEmpty
          ? null
          : _s(m['item_purchase_type']).trim(),

      category: _s(m['category']).trim().isEmpty
          ? null
          : _s(m['category']).trim(),

      isUpp: _b(m['is_upp']),

      minOrderUnit: _s(m['item_minimum_order_unit']).trim().isEmpty
          ? null
          : _s(m['item_minimum_order_unit']).trim(),

      subCategory: _s(m['sub_category']).trim().isEmpty
          ? null
          : _s(m['sub_category']).trim(),

      company: _s(m['company']).trim().isEmpty ? null : _s(m['company']).trim(),

      supplier: _s(m['supplier']).trim().isEmpty
          ? null
          : _s(m['supplier']).trim(),

      barcode: _s(m['barcode']).trim().isEmpty ? null : _s(m['barcode']).trim(),
    );
  }
}
