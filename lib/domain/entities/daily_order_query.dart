import 'daily_order_row.dart';

enum DailyOrderFieldType { text, number, date, boolean }

class DailyOrderField {
  const DailyOrderField(this.column, [this.type = DailyOrderFieldType.text]);

  final String column;
  final DailyOrderFieldType type;

  static const fields = <String, DailyOrderField>{
    'branch': DailyOrderField('branch'),
    'item_code': DailyOrderField('item_code'),
    'item_name': DailyOrderField('item_name'),
    'barcode': DailyOrderField('barcode'),
    'branch_stock': DailyOrderField('branch_stock', DailyOrderFieldType.number),
    'mismatch_stock': DailyOrderField(
      'mismatch_stock',
      DailyOrderFieldType.number,
    ),
    'store_stock': DailyOrderField('store_stock', DailyOrderFieldType.number),
    'pending_stock_received': DailyOrderField(
      'pending_stock_received',
      DailyOrderFieldType.number,
    ),
    'extra_qty_more_than_month': DailyOrderField(
      'extra_qty_more_than_month',
      DailyOrderFieldType.number,
    ),
    'max_adjustment_30d': DailyOrderField(
      'max_adjustment_30d',
      DailyOrderFieldType.number,
    ),
    'demand_for_30_days': DailyOrderField(
      'demand_for_30_days',
      DailyOrderFieldType.number,
    ),
    'reorder_point_min': DailyOrderField(
      'reorder_point_min',
      DailyOrderFieldType.number,
    ),
    'reorder_max': DailyOrderField('reorder_max', DailyOrderFieldType.number),
    'reorder_qty': DailyOrderField(
      'reorder_qty_num',
      DailyOrderFieldType.number,
    ),
    'final_reorder_qty_store_stock_gt_0': DailyOrderField(
      'final_reorder_qty_store_stock_gt_0',
    ),
    'goods_received_last_7_days': DailyOrderField('goods_received_last_7_days'),
    'date_of_last_qty_received_in_branch': DailyOrderField(
      'date_of_last_qty_received_in_branch',
    ),
    'qty_30_days_from_last_45d': DailyOrderField(
      'qty_30_days_from_last_45d',
      DailyOrderFieldType.number,
    ),
    'total_sold_qty_cash_last_90': DailyOrderField(
      'total_sold_qty_cash_last_90',
      DailyOrderFieldType.number,
    ),
    'total_sold_qty_online_last_90': DailyOrderField(
      'total_sold_qty_online_last_90',
      DailyOrderFieldType.number,
    ),
    'total_sold_qty_insurance_last_90': DailyOrderField(
      'total_sold_qty_insurance_last_90',
      DailyOrderFieldType.number,
    ),
    'total_sales_last_90_days': DailyOrderField(
      'total_sales_last_90_days',
      DailyOrderFieldType.number,
    ),
    'branch_formulary': DailyOrderField('branch_formulary'),
    'assortment_qty_base_stock': DailyOrderField(
      'assortment_qty_base_stock',
      DailyOrderFieldType.number,
    ),
    'assortment_by': DailyOrderField('assortment_by'),
    'reason': DailyOrderField('reason'),
    'reason_for_max_adjustment_30d': DailyOrderField('reason'),
    'assortment_start': DailyOrderField(
      'assortment_start',
      DailyOrderFieldType.date,
    ),
    'assortment_end': DailyOrderField(
      'assortment_end',
      DailyOrderFieldType.date,
    ),
    'tma_qty': DailyOrderField('tma_qty', DailyOrderFieldType.number),
    'tma_start': DailyOrderField('tma_start', DailyOrderFieldType.date),
    'tma_end': DailyOrderField('tma_end', DailyOrderFieldType.date),
    'item_purchase_type': DailyOrderField('item_purchase_type'),
    'sales_orientation': DailyOrderField('sales_orientation'),
    'category': DailyOrderField('category'),
    'sub_category': DailyOrderField('sub_category'),
    'company': DailyOrderField('company'),
    'supplier': DailyOrderField('supplier'),
    'indication': DailyOrderField('indication'),
    'active_ingredient': DailyOrderField('active_ingredient'),
    'pack_size': DailyOrderField('pack_size'),
    'concentration': DailyOrderField('concentration'),
    'product_type_form': DailyOrderField('product_type_form'),
    'retail_price': DailyOrderField('retail_price', DailyOrderFieldType.number),
    'vat': DailyOrderField('vat', DailyOrderFieldType.number),
    'is_upp': DailyOrderField('is_upp', DailyOrderFieldType.boolean),
    'item_minimum_order_unit': DailyOrderField(
      'item_minimum_order_unit',
      DailyOrderFieldType.number,
    ),
    'store_item_classifications': DailyOrderField('store_item_classifications'),
  };
}

enum DailyOrderOperator {
  contains('Contains'),
  doesNotContain('Does not contain'),
  startsWith('Starts with'),
  endsWith('Ends with'),
  equals('Is equal to'),
  notEqual('Is not equal to'),
  greaterThan('Is greater than'),
  atLeast('Is at least'),
  lessThan('Is less than'),
  atMost('Is at most'),
  isEmpty('Is blank'),
  isNotEmpty('Is not blank');

  const DailyOrderOperator(this.label);

  final String label;
  bool get needsValue => this != isEmpty && this != isNotEmpty;
}

typedef DailyOrderRule = ({DailyOrderOperator operator, String value});

class DailyOrderColumnFilter {
  DailyOrderColumnFilter(List<DailyOrderRule> rules, {required this.matchAny})
    : rules = List.unmodifiable(rules),
      values = null,
      excludeValues = false;

  DailyOrderColumnFilter.values(
    Set<String?> values, {
    this.excludeValues = false,
  }) : rules = const [],
       matchAny = false,
       values = Set.unmodifiable(values);

  final List<DailyOrderRule> rules;
  final bool matchAny;
  final Set<String?>? values;
  final bool excludeValues;

  bool get isActive =>
      values == null ? rules.isNotEmpty : !excludeValues || values!.isNotEmpty;
}

class DailyOrderQuery {
  DailyOrderQuery({
    required this.runDate,
    this.search = '',
    this.branch,
    Iterable<String> displayedBranchMatches = const [],
    Map<String, DailyOrderColumnFilter> filters = const {},
    this.sort = 'item_code',
    this.ascending = true,
  }) : displayedBranchMatches = List.unmodifiable(displayedBranchMatches),
       filters = Map.unmodifiable(filters);

  final String runDate;
  final String search;
  final String? branch;
  final List<String> displayedBranchMatches;
  final Map<String, DailyOrderColumnFilter> filters;
  final String sort;
  final bool ascending;
}

typedef DailyOrderCursor = ({
  String itemCode,
  String branch,
  Object? sortValue,
});

class DailyOrderBatch {
  const DailyOrderBatch(this.rows, this.next);

  final List<DailyOrderRow> rows;
  final DailyOrderCursor? next;
}

class DailyOrderFilterValues {
  const DailyOrderFilterValues(this.values, this.next);

  final List<String?> values;
  final String? next;
}
