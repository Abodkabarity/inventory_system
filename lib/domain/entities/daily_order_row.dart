// daily_order_row.dart

class DailyOrderRow {
  final String branch;
  final String itemCode;
  final String itemName;

  final num branchStock;
  final num mismatchStock;
  final num storeStock;
  final num pendingStockReceived;

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

  final bool? goodsReceivedLast7Days;

  final num? totalSoldQtyCashLast90;
  final num? totalSoldQtyOnlineLast90;
  final num? totalSoldQtyInsuranceLast90;

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
    bool? goodsReceivedLast7Days,
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
}
