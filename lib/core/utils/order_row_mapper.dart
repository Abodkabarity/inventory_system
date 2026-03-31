import '../../../../domain/entities/daily_order_row.dart';

class OrderRowMapper {
  static dynamic getValue(
    DailyOrderRow r,
    String key,
    Map<String, num> additional,
  ) {
    switch (key) {
      case 'row_no':
        return '';

      case 'additional_request':
        return additional[r.itemCode] ?? 0;

      case 'branch':
        return r.branch;

      case 'item_code':
        return r.itemCode;

      case 'item_name':
        return r.itemName;

      case 'goods_received_last_7_days':
        return r.goodsReceivedLast7Days ?? '';

      case 'branch_stock':
        return r.branchStock;

      case 'mismatch_stock':
        return r.mismatchStock;

      case 'store_stock':
        return r.storeStock;

      case 'pending_stock_received':
        return r.pendingStockReceived;

      case 'extra_qty_more_than_month':
        return r.extraQtyMoreThanMonth;

      case 'max_adjustment_30d':
        return r.maxAdjustment30d;

      case 'demand_for_30_days':
        return r.demandFor30Days;

      case 'reorder_point_min':
        return r.reorderPointMin ?? '';

      case 'reorder_max':
        return r.reorderMax ?? '';

      case 'reorder_qty':
        return r.reorderQtyNum;

      case 'final_reorder_qty_store_stock_gt_0':
        return r.finalReorderQtyStoreStockGt0;

      case 'date_of_last_qty_received_in_branch':
        return r.dateOfLastQtyReceivedInBranch ?? '';

      case 'total_sold_qty_cash_last_90':
        return r.totalSoldQtyCashLast90 ?? '';

      case 'total_sold_qty_online_last_90':
        return r.totalSoldQtyOnlineLast90 ?? '';

      case 'total_sold_qty_insurance_last_90':
        return r.totalSoldQtyInsuranceLast90 ?? '';

      case 'qty_30_days_from_last_45d':
        return r.qty30DaysFromLast45d;

      case 'branch_formulary':
        return r.branchFormulary ?? '';

      case 'assortment_qty_base_stock':
        return r.assortmentQtyBaseStock ?? '';

      case 'assortment_by':
        return r.assortmentBy ?? '';

      case 'reason':
        return r.reason ?? '';

      case 'assortment_start':
        return r.assortmentStart ?? '';

      case 'assortment_end':
        return r.assortmentEnd ?? '';

      case 'tma_qty':
        return r.tmaQty ?? '';

      case 'tma_start':
        return r.tmaStart ?? '';

      case 'tma_end':
        return r.tmaEnd ?? '';

      case 'item_purchase_type':
        return r.itemPurchaseType ?? '';

      case 'sales_orientation':
        return r.salesOrientation ?? '';

      case 'category':
        return r.category ?? '';

      case 'sub_category':
        return r.subCategory ?? '';

      case 'company':
        return r.company ?? '';

      case 'supplier':
        return r.supplier ?? '';

      case 'indication':
        return r.indication ?? '';

      case 'active_ingredient':
        return r.activeIngredient ?? '';

      case 'pack_size':
        return r.packSize ?? '';

      case 'concentration':
        return r.concentration ?? '';

      case 'product_type_form':
        return r.productTypeForm ?? '';

      case 'retail_price':
        return r.retailPrice ?? '';

      case 'vat':
        return r.vat ?? '';

      case 'is_upp':
        return r.isUpp == true ? 'YES' : (r.isUpp == false ? 'NO' : '');

      case 'upp_thiqa':
        return r.uppThiqa == true ? 'YES' : (r.uppThiqa == false ? 'NO' : '');

      case 'upp_basic':
        return r.uppBasic == true ? 'YES' : (r.uppBasic == false ? 'NO' : '');

      case 'tier':
        return r.tier ?? '';

      case 'item_minimum_order_unit':
        return r.minOrderUnit ?? '';

      case 'barcode':
        return r.barcode ?? '';

      case 'store_item_classifications':
        return r.storeItemClassifications ?? '';

      default:
        return '';
    }
  }
}
