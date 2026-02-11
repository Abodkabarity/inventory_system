import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/item_model.dart';

class SupabaseItemRemoteDs {
  final SupabaseClient client;
  SupabaseItemRemoteDs(this.client);

  /// Pull from item_report with your conditions:
  /// status = active, is_block = false, item_status starts with 1 or 2
  Future<List<ItemModel>> getCatalogItems({
    int limit = 50,
    int offset = 0,
    String? search,
  }) async {
    var q = client
        .from('item_report')
        .select('item_code, item_name, barcode, status, is_block, item_status')
        .eq('is_block', false)
        .ilike('status', 'active');

    // item_status starts with 1 or 2
    // Supabase PostgREST supports OR filter syntax:
    q = q.or('item_status.like.1%,item_status.like.2%');

    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      // search by name or code or barcode
      q = q.or('item_name.ilike.%$s%,item_code.ilike.%$s%,barcode.ilike.%$s%');
    }

    final data = await q
        .order('item_name', ascending: true)
        .range(offset, offset + limit - 1);

    return (data as List)
        .map((e) => ItemModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
