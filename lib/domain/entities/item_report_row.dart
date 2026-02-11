class ItemReportRow {
  final String itemCode;
  final String itemName;
  final String category;
  final String subCategory;
  final String company;
  final String supplier;
  final String indication;
  final String mainIngredient;
  final String packSize;
  final String concentration;
  final String productTypeForm;
  final num? retailPrice;
  final num? vat;
  final bool? isUpp;
  final String tier;
  final String itemMinimumOrderUnit;
  final String barcode;
  final String storeItemClassifications;
  final String itemPurchaseType;
  final String salesOrientation;

  // حقول غير موجودة في item_report (نتركها لاحقًا)
  final String branch;

  const ItemReportRow({
    required this.itemCode,
    required this.itemName,
    required this.category,
    required this.subCategory,
    required this.company,
    required this.supplier,
    required this.indication,
    required this.mainIngredient,
    required this.packSize,
    required this.concentration,
    required this.productTypeForm,
    required this.retailPrice,
    required this.vat,
    required this.isUpp,
    required this.tier,
    required this.itemMinimumOrderUnit,
    required this.barcode,
    required this.storeItemClassifications,
    required this.itemPurchaseType,
    required this.salesOrientation,
    this.branch = '',
  });
}
