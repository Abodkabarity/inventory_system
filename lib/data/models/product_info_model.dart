import '../../domain/entities/product_info.dart';

class ProductInfoModel extends ProductInfo {
  const ProductInfoModel({
    required super.itemCode,
    super.category,
    super.subCategory,
    super.company,
    super.supplier,
    super.barcode,
    super.minOrderUnit,
    super.itemPurchaseType,
    super.branchFormulary,
    super.assortmentQtyBaseStock,
    super.assortmentBy,
    super.isUpp,
    super.uppThiqa,
    super.uppBasic,
  });

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static num? _nOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return num.tryParse(s.replaceAll(',', ''));
  }

  static bool? _bOrNull(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
    return null;
  }

  factory ProductInfoModel.fromMap(Map<String, dynamic> m) {
    return ProductInfoModel(
      itemCode: _s(m['item_code']),
      category: _s(m['category']).isEmpty ? null : _s(m['category']),
      subCategory: _s(m['sub_category']).isEmpty ? null : _s(m['sub_category']),
      company: _s(m['company']).isEmpty ? null : _s(m['company']),
      supplier: _s(m['supplier']).isEmpty ? null : _s(m['supplier']),
      barcode: _s(m['barcode']).isEmpty ? null : _s(m['barcode']),
      minOrderUnit: _nOrNull(
        m['item_minimum_order_unit'] ?? m['min_order_unit'],
      ),
      itemPurchaseType: _s(m['item_purchase_type'] ?? m['item_status']).isEmpty
          ? null
          : _s(m['item_purchase_type'] ?? m['item_status']),
      branchFormulary: _s(m['branch_formulary']).isEmpty
          ? null
          : _s(m['branch_formulary']),
      assortmentQtyBaseStock: _nOrNull(m['assortment_qty_base_stock']),
      assortmentBy: _s(m['assortment_by']).isEmpty
          ? null
          : _s(m['assortment_by']),
      isUpp: _bOrNull(m['is_upp']),
    );
  }
}
