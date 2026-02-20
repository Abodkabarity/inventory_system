class DailyOrderRow {
  final String branch;
  final String itemCode;
  final String itemName;

  final num branchStock;
  final num mismatchStock;
  final num storeStock;
  final num pendingStockReceived;

  // ✅ IMPORTANT
  final bool? isLimitedStock;

  final num extraQtyMoreThanMonth;
  final num maxAdjustment30d;
  final num demandFor30Days;

  final String finalReorderQtyStoreStockGt0;
  final num qty30DaysFromLast45d;

  // ✅ From v_daily_order_latest directly
  final String? branchFormulary;
  final String? assortmentQtyBaseStock;
  final String? assortmentBy;
  final String? itemPurchaseType;
  final String? category;

  final bool? isUpp;
  final bool? uppThiqa;
  final bool? uppBasic;

  final String? minOrderUnit;

  // Optional (only if موجودة في view)
  final String? subCategory;
  final String? company;
  final String? supplier;
  final String? barcode;

  const DailyOrderRow({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.branchStock,
    required this.mismatchStock,
    required this.storeStock,
    required this.pendingStockReceived,

    // ✅ ADDED
    this.isLimitedStock,

    required this.extraQtyMoreThanMonth,
    required this.maxAdjustment30d,
    required this.demandFor30Days,
    required this.finalReorderQtyStoreStockGt0,
    required this.qty30DaysFromLast45d,
    this.branchFormulary,
    this.assortmentQtyBaseStock,
    this.assortmentBy,
    this.itemPurchaseType,
    this.category,
    this.isUpp,
    this.uppThiqa,
    this.uppBasic,
    this.minOrderUnit,
    this.subCategory,
    this.company,
    this.supplier,
    this.barcode,
  });

  DailyOrderRow copyWith({
    String? branch,
    String? itemCode,
    String? itemName,
    num? branchStock,
    num? mismatchStock,
    num? storeStock,
    num? pendingStockReceived,

    // ✅ ADDED
    bool? isLimitedStock,

    num? extraQtyMoreThanMonth,
    num? maxAdjustment30d,
    num? demandFor30Days,
    String? finalReorderQtyStoreStockGt0,
    num? qty30DaysFromLast45d,
    String? branchFormulary,
    String? assortmentQtyBaseStock,
    String? assortmentBy,
    String? itemPurchaseType,
    String? category,
    bool? isUpp,
    bool? uppThiqa,
    bool? uppBasic,
    String? minOrderUnit,
    String? subCategory,
    String? company,
    String? supplier,
    String? barcode,
  }) {
    return DailyOrderRow(
      branch: branch ?? this.branch,
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      branchStock: branchStock ?? this.branchStock,
      mismatchStock: mismatchStock ?? this.mismatchStock,
      storeStock: storeStock ?? this.storeStock,
      pendingStockReceived: pendingStockReceived ?? this.pendingStockReceived,

      // ✅ ADDED
      isLimitedStock: isLimitedStock ?? this.isLimitedStock,

      extraQtyMoreThanMonth:
          extraQtyMoreThanMonth ?? this.extraQtyMoreThanMonth,
      maxAdjustment30d: maxAdjustment30d ?? this.maxAdjustment30d,
      demandFor30Days: demandFor30Days ?? this.demandFor30Days,
      finalReorderQtyStoreStockGt0:
          finalReorderQtyStoreStockGt0 ?? this.finalReorderQtyStoreStockGt0,
      qty30DaysFromLast45d: qty30DaysFromLast45d ?? this.qty30DaysFromLast45d,
      branchFormulary: branchFormulary ?? this.branchFormulary,
      assortmentQtyBaseStock:
          assortmentQtyBaseStock ?? this.assortmentQtyBaseStock,
      assortmentBy: assortmentBy ?? this.assortmentBy,
      itemPurchaseType: itemPurchaseType ?? this.itemPurchaseType,
      category: category ?? this.category,
      isUpp: isUpp ?? this.isUpp,
      uppThiqa: uppThiqa ?? this.uppThiqa,
      uppBasic: uppBasic ?? this.uppBasic,
      minOrderUnit: minOrderUnit ?? this.minOrderUnit,
      subCategory: subCategory ?? this.subCategory,
      company: company ?? this.company,
      supplier: supplier ?? this.supplier,
      barcode: barcode ?? this.barcode,
    );
  }
}
