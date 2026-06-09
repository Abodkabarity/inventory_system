// daily_order_row.dart

class DailyOrderRow {
  final String branch;
  final String itemCode;
  final String itemName;

  final num branchStock;
  final num mismatchStock;
  final num storeStock;
  final num pendingStockReceived;
  final int? totalReorderToday;
  final bool? isLimitedStock;

  final num extraQtyMoreThanMonth;
  final num maxAdjustment30d;
  final num demandFor30Days;

  final String finalReorderQtyStoreStockGt0;
  final num qty30DaysFromLast45d;

  // Numeric reorder qty from DB (reorder_qty_num)
  final num reorderQtyNum;

  // Optional: aggregated total reorder for same item across all branches
  final int totalReorderAllBranches;

  // From v_daily_order_latest (optional)
  final String? branchFormulary;
  final String? assortmentQtyBaseStock;
  final String? assortmentBy;
  final String? itemPurchaseType;
  final String? salesOrientation;
  final String? category;
  final String? subCategory;

  final bool? isUpp;
  final bool? uppThiqa;
  final bool? uppBasic;

  final String? tier;
  final String? minOrderUnit;

  final String? company;
  final String? supplier;

  final String? barcode;

  // Added optional columns (based on your columns list)
  final num? reorderPointMin;
  final num? reorderMax;
  final num? reorderQty;
  final String? dateOfLastQtyReceivedInBranch;

  final String? reason;
  final String? assortmentStart;
  final String? assortmentEnd;

  final num? tmaQty;
  final String? tmaStart;
  final String? tmaEnd;

  final String? indication;
  final String? activeIngredient;
  final String? packSize;
  final String? concentration;
  final String? productTypeForm;

  final num? retailPrice;
  final num? vat;

  final String? storeItemClassifications;

  final String? goodsReceivedLast7Days;

  final num? totalSoldQtyCashLast90;
  final num? totalSoldQtyOnlineLast90;
  final num? totalSoldQtyInsuranceLast90;
  final num? totalSalesLast90Days;
  const DailyOrderRow({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.branchStock,
    required this.mismatchStock,
    required this.storeStock,
    required this.pendingStockReceived,
    this.isLimitedStock,
    required this.extraQtyMoreThanMonth,
    required this.maxAdjustment30d,
    required this.demandFor30Days,
    required this.finalReorderQtyStoreStockGt0,
    required this.qty30DaysFromLast45d,
    required this.reorderQtyNum,
    required this.totalReorderAllBranches,
    this.branchFormulary,
    this.assortmentQtyBaseStock,
    this.assortmentBy,
    this.itemPurchaseType,
    this.salesOrientation,
    this.category,
    this.subCategory,
    this.isUpp,
    this.uppThiqa,
    this.uppBasic,
    this.tier,
    this.minOrderUnit,
    this.company,
    this.supplier,
    this.barcode,
    this.reorderPointMin,
    this.reorderMax,
    this.reorderQty,
    this.dateOfLastQtyReceivedInBranch,
    this.reason,
    this.assortmentStart,
    this.assortmentEnd,
    this.tmaQty,
    this.tmaStart,
    this.tmaEnd,
    this.indication,
    this.activeIngredient,
    this.packSize,
    this.concentration,
    this.productTypeForm,
    this.retailPrice,
    this.vat,
    this.storeItemClassifications,
    this.goodsReceivedLast7Days,
    this.totalSoldQtyCashLast90,
    this.totalSoldQtyOnlineLast90,
    this.totalSoldQtyInsuranceLast90,
    this.totalReorderToday,
    this.totalSalesLast90Days,
  });

  DailyOrderRow copyWith({
    String? branch,
    String? itemCode,
    String? itemName,
    num? branchStock,
    num? mismatchStock,
    num? storeStock,
    num? pendingStockReceived,
    bool? isLimitedStock,
    num? extraQtyMoreThanMonth,
    num? maxAdjustment30d,
    num? demandFor30Days,
    String? finalReorderQtyStoreStockGt0,
    num? qty30DaysFromLast45d,
    num? reorderQtyNum,
    int? totalReorderAllBranches,
    String? branchFormulary,
    String? assortmentQtyBaseStock,
    String? assortmentBy,
    String? itemPurchaseType,
    String? salesOrientation,
    String? category,
    String? subCategory,
    bool? isUpp,
    bool? uppThiqa,
    num? totalSalesLast90Days,
    bool? uppBasic,
    String? tier,
    String? minOrderUnit,
    String? company,
    String? supplier,
    String? barcode,
    num? reorderPointMin,
    num? reorderMax,
    num? reorderQty,
    String? dateOfLastQtyReceivedInBranch,
    String? reason,
    String? assortmentStart,
    String? assortmentEnd,
    num? tmaQty,
    String? tmaStart,
    String? tmaEnd,
    String? indication,
    String? activeIngredient,
    String? packSize,
    String? concentration,
    String? productTypeForm,
    num? retailPrice,
    num? vat,
    String? storeItemClassifications,
    String? goodsReceivedLast7Days,
    num? totalSoldQtyCashLast90,
    num? totalSoldQtyOnlineLast90,
    num? totalSoldQtyInsuranceLast90,
  }) {
    return DailyOrderRow(
      branch: branch ?? this.branch,
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      branchStock: branchStock ?? this.branchStock,
      mismatchStock: mismatchStock ?? this.mismatchStock,
      storeStock: storeStock ?? this.storeStock,
      pendingStockReceived: pendingStockReceived ?? this.pendingStockReceived,
      isLimitedStock: isLimitedStock ?? this.isLimitedStock,
      extraQtyMoreThanMonth:
          extraQtyMoreThanMonth ?? this.extraQtyMoreThanMonth,
      maxAdjustment30d: maxAdjustment30d ?? this.maxAdjustment30d,
      demandFor30Days: demandFor30Days ?? this.demandFor30Days,
      finalReorderQtyStoreStockGt0:
          finalReorderQtyStoreStockGt0 ?? this.finalReorderQtyStoreStockGt0,
      qty30DaysFromLast45d: qty30DaysFromLast45d ?? this.qty30DaysFromLast45d,
      reorderQtyNum: reorderQtyNum ?? this.reorderQtyNum,
      totalReorderAllBranches:
          totalReorderAllBranches ?? this.totalReorderAllBranches,
      branchFormulary: branchFormulary ?? this.branchFormulary,
      assortmentQtyBaseStock:
          assortmentQtyBaseStock ?? this.assortmentQtyBaseStock,
      assortmentBy: assortmentBy ?? this.assortmentBy,
      totalSalesLast90Days: totalSalesLast90Days ?? this.totalSalesLast90Days,
      itemPurchaseType: itemPurchaseType ?? this.itemPurchaseType,
      salesOrientation: salesOrientation ?? this.salesOrientation,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      isUpp: isUpp ?? this.isUpp,
      uppThiqa: uppThiqa ?? this.uppThiqa,
      uppBasic: uppBasic ?? this.uppBasic,
      tier: tier ?? this.tier,
      minOrderUnit: minOrderUnit ?? this.minOrderUnit,
      company: company ?? this.company,
      supplier: supplier ?? this.supplier,
      barcode: barcode ?? this.barcode,
      reorderPointMin: reorderPointMin ?? this.reorderPointMin,
      reorderMax: reorderMax ?? this.reorderMax,
      reorderQty: reorderQty ?? this.reorderQty,
      dateOfLastQtyReceivedInBranch:
          dateOfLastQtyReceivedInBranch ?? this.dateOfLastQtyReceivedInBranch,
      reason: reason ?? this.reason,
      assortmentStart: assortmentStart ?? this.assortmentStart,
      assortmentEnd: assortmentEnd ?? this.assortmentEnd,
      tmaQty: tmaQty ?? this.tmaQty,
      tmaStart: tmaStart ?? this.tmaStart,
      tmaEnd: tmaEnd ?? this.tmaEnd,
      indication: indication ?? this.indication,
      activeIngredient: activeIngredient ?? this.activeIngredient,
      packSize: packSize ?? this.packSize,
      concentration: concentration ?? this.concentration,
      productTypeForm: productTypeForm ?? this.productTypeForm,
      retailPrice: retailPrice ?? this.retailPrice,
      vat: vat ?? this.vat,
      storeItemClassifications:
          storeItemClassifications ?? this.storeItemClassifications,
      goodsReceivedLast7Days:
          goodsReceivedLast7Days ?? this.goodsReceivedLast7Days,
      totalSoldQtyCashLast90:
          totalSoldQtyCashLast90 ?? this.totalSoldQtyCashLast90,
      totalSoldQtyOnlineLast90:
          totalSoldQtyOnlineLast90 ?? this.totalSoldQtyOnlineLast90,
      totalSoldQtyInsuranceLast90:
          totalSoldQtyInsuranceLast90 ?? this.totalSoldQtyInsuranceLast90,
    );
  }

  factory DailyOrderRow.fromMap(Map<String, dynamic> map) {
    num parseNum(dynamic v) => num.tryParse((v ?? '0').toString()) ?? 0;

    String str(dynamic v) => (v ?? '').toString();

    return DailyOrderRow(
      /// 🔹 BASIC
      branch: str(map['branch']),
      itemCode: str(map['item_code']),
      itemName: str(map['item_name']),

      /// 🔹 STOCK
      branchStock: parseNum(map['branch_stock']),
      mismatchStock: parseNum(map['mismatch_stock']),
      storeStock: parseNum(map['store_stock']),
      pendingStockReceived: parseNum(map['pending_stock_received']),

      /// 🔹 DEMAND
      extraQtyMoreThanMonth: parseNum(map['extra_qty_more_than_month']),
      maxAdjustment30d: parseNum(map['max_adjustment_30d']),
      demandFor30Days: parseNum(map['demand_for_30_days']),

      /// 🔹 REORDER
      finalReorderQtyStoreStockGt0: str(
        map['final_reorder_qty_store_stock_gt_0'],
      ),
      qty30DaysFromLast45d: parseNum(map['qty_30_days_from_last_45d']),
      reorderQtyNum: parseNum(map['reorder_qty_num']),

      /// 🔹 EXTRA
      totalReorderAllBranches: 0,

      /// 🔹 META
      branchFormulary: str(map['branch_formulary']),
      assortmentQtyBaseStock: str(map['assortment_qty_base_stock']),
      assortmentBy: str(map['assortment_by']),
      itemPurchaseType: str(map['item_purchase_type']),
      salesOrientation: str(map['sales_orientation']),
      category: str(map['category']),
      subCategory: str(map['sub_category']),

      /// 🔹 BOOL
      isUpp: map['is_upp'] == true,

      /// 🔹 UNIT + BARCODE
      minOrderUnit: str(map['item_minimum_order_unit']),
      barcode: str(map['barcode']),

      /// 🔹 LIMITS
      reorderPointMin: parseNum(map['reorder_point_min']),
      reorderMax: parseNum(map['reorder_max']),
      reorderQty: parseNum(map['reorder_qty']),

      /// 🔹 DATES
      dateOfLastQtyReceivedInBranch: str(
        map['date_of_last_qty_received_in_branch'],
      ),

      /// 🔹 REASON
      reason: str(map['reason']),

      /// 🔹 TMA
      tmaQty: parseNum(map['tma_qty']),
      tmaStart: str(map['tma_start']),
      tmaEnd: str(map['tma_end']),

      /// 🔹 MEDICAL
      indication: str(map['indication']),
      activeIngredient: str(map['active_ingredient']),

      /// 🔹 PRODUCT
      packSize: str(map['pack_size']),
      concentration: str(map['concentration']),
      productTypeForm: str(map['product_type_form']),

      /// 🔹 PRICE
      retailPrice: parseNum(map['retail_price']),
      vat: parseNum(map['vat']),

      /// 🔹 CLASSIFICATION
      storeItemClassifications: str(map['store_item_classifications']),

      /// 🔹 GOODS RECEIVED
      goodsReceivedLast7Days: (map['goods_received_last_7_days'] ?? ''),
      totalSoldQtyCashLast90: parseNum(map['total_sold_qty_cash_last_90']),

      totalSoldQtyOnlineLast90: parseNum(map['total_sold_qty_online_last_90']),

      totalSoldQtyInsuranceLast90: parseNum(
        map['total_sold_qty_insurance_last_90'],
      ),

      totalSalesLast90Days: parseNum(map['total_sales_last_90_days']),
    );
  }
}
