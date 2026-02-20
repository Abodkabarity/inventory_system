class ProductInfo {
  final String itemCode;
  final String? category;
  final String? subCategory;
  final String? company;
  final String? supplier;
  final String? barcode;

  final num? minOrderUnit;

  final String? itemPurchaseType;
  final String? branchFormulary;
  final num? assortmentQtyBaseStock;
  final String? assortmentBy;

  final bool? isUpp;
  final bool? uppThiqa;
  final bool? uppBasic;

  const ProductInfo({
    required this.itemCode,
    this.category,
    this.subCategory,
    this.company,
    this.supplier,
    this.barcode,
    this.minOrderUnit,
    this.itemPurchaseType,
    this.branchFormulary,
    this.assortmentQtyBaseStock,
    this.assortmentBy,
    this.isUpp,
    this.uppThiqa,
    this.uppBasic,
  });
}
