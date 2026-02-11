import '../../domain/entities/item_report_row.dart';

class ItemReportRowModel extends ItemReportRow {
  const ItemReportRowModel({
    required super.itemCode,
    required super.itemName,
    required super.category,
    required super.subCategory,
    required super.company,
    required super.supplier,
    required super.indication,
    required super.mainIngredient,
    required super.packSize,
    required super.concentration,
    required super.productTypeForm,
    required super.retailPrice,
    required super.vat,
    required super.isUpp,
    required super.tier,
    required super.itemMinimumOrderUnit,
    required super.barcode,
    required super.storeItemClassifications,
    required super.itemPurchaseType,
    required super.salesOrientation,
    super.branch,
  });

  factory ItemReportRowModel.fromJson(Map<String, dynamic> json) {
    return ItemReportRowModel(
      itemCode: (json['item_code'] ?? '').toString(),
      itemName: (json['item_name'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      subCategory: (json['sub_category'] ?? '').toString(),
      company: (json['company'] ?? '').toString(),
      supplier: (json['supplier'] ?? '').toString(),
      indication: (json['indication'] ?? '').toString(),
      mainIngredient: (json['main_ingredient'] ?? '').toString(),
      packSize: (json['pack_size_volume'] ?? '').toString(),
      concentration: (json['concentration'] ?? '').toString(),
      productTypeForm: (json['product_type'] ?? '').toString(),
      retailPrice: json['retail'] as num?,
      vat: json['tax_percent'] as num?,
      isUpp: json['is_upp'] as bool?,
      tier: (json['insurance_tier'] ?? '').toString(),
      itemMinimumOrderUnit: (json['min_order_unit'] ?? '').toString(),
      barcode: (json['barcode'] ?? '').toString(),
      storeItemClassifications: (json['store_classification'] ?? '').toString(),
      itemPurchaseType: (json['item_status'] ?? '').toString(),
      salesOrientation: (json['item_priority'] ?? '').toString(),
    );
  }
}
