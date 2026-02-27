// daily_order_row_model.dart

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
    super.isLimitedStock,
    required super.extraQtyMoreThanMonth,
    required super.maxAdjustment30d,
    required super.demandFor30Days,
    required super.finalReorderQtyStoreStockGt0,
    required super.qty30DaysFromLast45d,
    required super.reorderQtyNum,
    required super.totalReorderAllBranches,
    super.branchFormulary,
    super.assortmentQtyBaseStock,
    super.assortmentBy,
    super.itemPurchaseType,
    super.salesOrientation,
    super.category,
    super.subCategory,
    super.isUpp,
    super.uppThiqa,
    super.uppBasic,
    super.tier,
    super.minOrderUnit,
    super.company,
    super.supplier,
    super.barcode,
    super.reorderPointMin,
    super.reorderMax,
    super.reorderQty,
    super.dateOfLastQtyReceivedInBranch,
    super.reason,
    super.assortmentStart,
    super.assortmentEnd,
    super.tmaQty,
    super.tmaStart,
    super.tmaEnd,
    super.indication,
    super.activeIngredient,
    super.packSize,
    super.concentration,
    super.productTypeForm,
    super.retailPrice,
    super.vat,
    super.storeItemClassifications,
    super.goodsReceivedLast7Days,
    super.totalSoldQtyCashLast90,
    super.totalSoldQtyOnlineLast90,
    super.totalSoldQtyInsuranceLast90,
  });

  static String _s(dynamic v) => (v ?? '').toString();

  static String? _sn(dynamic v) {
    final s = _s(v).trim();
    return s.isEmpty ? null : s;
  }

  static num _n(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    return num.tryParse(s.replaceAll(',', '')) ?? 0;
  }

  static num? _nn(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    if (v is num) return v;
    return num.tryParse(s.replaceAll(',', ''));
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
    if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
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
      isLimitedStock: _b(m['is_limited_stock']),
      extraQtyMoreThanMonth: _n(m['extra_qty_more_than_month']),
      maxAdjustment30d: _n(m['max_adjustment_30d']),
      demandFor30Days: _n(m['demand_for_30_days']),
      finalReorderQtyStoreStockGt0: _s(
        m['final_reorder_qty_store_stock_gt_0'],
      ).trim(),
      qty30DaysFromLast45d: _n(m['qty_30_days_from_last_45d']),
      reorderQtyNum: _n(m['reorder_qty_num']),
      totalReorderAllBranches: _i(m['total_reorder_all_branches']),
      branchFormulary: _sn(m['branch_formulary']),
      assortmentQtyBaseStock: _sn(m['assortment_qty_base_stock']),
      assortmentBy: _sn(m['assortment_by']),
      itemPurchaseType: _sn(m['item_purchase_type']),
      salesOrientation: _sn(m['sales_orientation']),
      category: _sn(m['category']),
      subCategory: _sn(m['sub_category']),
      isUpp: _b(m['is_upp']),
      uppThiqa: _b(m['upp_thiqa']),
      uppBasic: _b(m['upp_basic']),
      tier: _sn(m['tier']),
      minOrderUnit: _sn(m['item_minimum_order_unit']),
      company: _sn(m['company']),
      supplier: _sn(m['supplier']),
      barcode: _sn(m['barcode']),
      reorderPointMin: _nn(m['reorder_point_min']),
      reorderMax: _nn(m['reorder_max']),
      reorderQty: _nn(m['reorder_qty']),
      dateOfLastQtyReceivedInBranch: _sn(
        m['date_of_last_qty_received_in_branch'],
      ),
      reason: _sn(m['reason']),
      assortmentStart: _sn(m['assortment_start']),
      assortmentEnd: _sn(m['assortment_end']),
      tmaQty: _nn(m['tma_qty']),
      tmaStart: _sn(m['tma_start']),
      tmaEnd: _sn(m['tma_end']),
      indication: _sn(m['indication']),
      activeIngredient: _sn(m['active_ingredient']),
      packSize: _sn(m['pack_size']),
      concentration: _sn(m['concentration']),
      productTypeForm: _sn(m['product_type_form']),
      retailPrice: _nn(m['retail_price']),
      vat: _nn(m['vat']),
      storeItemClassifications: _sn(m['store_item_classifications']),
      goodsReceivedLast7Days: _b(m['goods_received_last_7_days']),
      totalSoldQtyCashLast90: _nn(m['total_sold_qty_cash_last_90']),
      totalSoldQtyOnlineLast90: _nn(m['total_sold_qty_online_last_90']),
      totalSoldQtyInsuranceLast90: _nn(m['total_sold_qty_insurance_last_90']),
    );
  }
}
