import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/item_report_row_model.dart';

class ItemReportRemoteDs {
  final SupabaseClient client;
  ItemReportRemoteDs(this.client);

  static const _select =
      'item_code,item_name,category,sub_category,company,supplier,'
      'indication,main_ingredient,pack_size_volume,concentration,product_type,'
      'retail,tax_percent,is_upp,insurance_tier,min_order_unit,'
      'barcode,store_classification,item_status,item_priority';

  Future<int> getTotalCountSlowButCompatible() async {
    final res = await client.from('item_report').select('item_code');
    return (res as List).length;
  }

  Future<List<ItemReportRowModel>> fetchPage({
    required int from,
    required int to,
  }) async {
    final data = await client
        .from('item_report')
        .select(_select)
        .range(from, to);
    return (data as List)
        .map((e) => ItemReportRowModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
