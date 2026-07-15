import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/purchase_status_record.dart';

class PurchaseStatusRemoteDs {
  final SupabaseClient client;

  static const int _recordsBatchSize = 1000;
  static const String _recordsSelect =
      'id,item_code,item_name,status_id,status_date,alternative_item_code,'
      'alternative_item_name,note,purchase_status,category,supplier,updated_at,'
      'workflow_status,review_origin,required_quantity,missing_request_count,'
      'missing_last_report_date,source,'
      'purchase_status_options(name)';

  PurchaseStatusRemoteDs(this.client);

  Future<List<PurchaseStatusOption>> fetchStatuses() async {
    final rows = await client
        .from('purchase_status_options')
        .select('id,name')
        .eq('is_active', true)
        .order('display_order')
        .order('name');
    return (rows as List)
        .map((row) => PurchaseStatusOption.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<PurchaseStatusOption> addStatus(String name) async {
    final row = await client
        .from('purchase_status_options')
        .insert({'name': name.trim()})
        .select('id,name')
        .single();
    return PurchaseStatusOption.fromMap(row);
  }

  Future<List<PurchaseStatusRecord>> fetchRecords() async {
    final records = <PurchaseStatusRecord>[];
    var from = 0;

    while (true) {
      final rows = await client
          .from('purchase_status_items')
          .select(_recordsSelect)
          .order('workflow_status', ascending: false)
          .order('review_origin')
          .order('missing_last_report_date', ascending: false)
          .order('updated_at', ascending: false)
          .order('id', ascending: false)
          .range(from, from + _recordsBatchSize - 1);
      final page = (rows as List)
          .map(
            (row) => PurchaseStatusRecord.fromMap(row as Map<String, dynamic>),
          )
          .toList();
      records.addAll(page);
      if (page.length < _recordsBatchSize) break;
      from += _recordsBatchSize;
    }

    records.sort(_compareReviewPriority);
    return records;
  }

  static int _compareReviewPriority(
    PurchaseStatusRecord left,
    PurchaseStatusRecord right,
  ) {
    final workflowComparison = _workflowRank(
      left,
    ).compareTo(_workflowRank(right));
    if (workflowComparison != 0) return workflowComparison;

    if (left.isPending && right.isPending) {
      final originComparison = _originRank(
        left.reviewOrigin,
      ).compareTo(_originRank(right.reviewOrigin));
      if (originComparison != 0) return originComparison;
    }

    final reportDateComparison = _compareNewestFirst(
      left.missingLastReportDate,
      right.missingLastReportDate,
    );
    if (reportDateComparison != 0) return reportDateComparison;

    final updatedComparison = _compareNewestFirst(
      left.updatedAt,
      right.updatedAt,
    );
    if (updatedComparison != 0) return updatedComparison;
    return right.id.compareTo(left.id);
  }

  static int _workflowRank(PurchaseStatusRecord record) =>
      record.isPending ? 0 : 1;

  static int _originRank(String origin) => switch (origin) {
    'new' => 0,
    'repeated' => 1,
    _ => 2,
  };

  static int _compareNewestFirst(DateTime? left, DateTime? right) {
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  }

  Future<List<PurchaseProductSuggestion>> searchProducts(
    String query, {
    int limit = 12,
  }) async {
    final cleaned = query.trim().replaceAll(RegExp(r'[,()%]'), ' ');
    if (cleaned.isEmpty) return const [];
    final rows = await client
        .from('item_report')
        .select('item_code,item_name,item_status,category,supplier')
        .or('item_code.ilike.%$cleaned%,item_name.ilike.%$cleaned%')
        .order('item_name')
        .limit(limit);
    return (rows as List)
        .map(
          (row) =>
              PurchaseProductSuggestion.fromMap(row as Map<String, dynamic>),
        )
        .toList();
  }

  Future<PurchaseProductSuggestion?> resolveProduct(String value) async {
    final suggestions = await searchProducts(value, limit: 20);
    final wanted = value.trim().toLowerCase();
    for (final product in suggestions) {
      if (product.itemCode.trim().toLowerCase() == wanted ||
          product.itemName.trim().toLowerCase() == wanted) {
        return product;
      }
    }
    return null;
  }

  Future<PurchaseStatusRecord?> findExisting(
    String itemCode, {
    String itemName = '',
  }) async {
    Map<String, dynamic>? row;
    if (itemCode.trim().isNotEmpty) {
      row = await client
          .from('purchase_status_items')
          .select('*,purchase_status_options(name)')
          .eq('item_code', itemCode.trim())
          .limit(1)
          .maybeSingle();
    }
    if (row == null && itemName.trim().isNotEmpty) {
      row = await client
          .from('purchase_status_items')
          .select('*,purchase_status_options(name)')
          .ilike('item_name', itemName.trim())
          .limit(1)
          .maybeSingle();
    }
    if (row == null) return null;
    return PurchaseStatusRecord.fromMap(row);
  }

  Future<void> save({
    int? id,
    required PurchaseProductSuggestion product,
    required int statusId,
    required DateTime statusDate,
    PurchaseProductSuggestion? alternative,
    required String note,
  }) async {
    final userId = client.auth.currentUser?.id;
    final payload = <String, dynamic>{
      'item_code': product.itemCode.trim().isEmpty ? null : product.itemCode,
      'item_name': product.itemName,
      'status_id': statusId,
      'status_date': statusDate.toIso8601String().split('T').first,
      'alternative_item_code': alternative?.itemCode,
      'alternative_item_name': alternative?.itemName,
      'note': note.trim().isEmpty ? null : note.trim(),
      'purchase_status': product.purchaseStatus,
      'category': product.category,
      'supplier': product.supplier,
      'workflow_status': 'complete',
      'completed_at': DateTime.now().toIso8601String(),
      'completed_by': userId,
      'updated_by': userId,
    };
    if (id == null) {
      payload['created_by'] = userId;
      await client.from('purchase_status_items').insert(payload);
    } else {
      await client.from('purchase_status_items').update(payload).eq('id', id);
    }
  }

  Future<void> delete(int id) async {
    await client.from('purchase_status_items').delete().eq('id', id);
  }

  Future<Map<String, dynamic>> importExcelRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final result = await client.rpc(
      'import_purchase_status_excel',
      params: {'p_rows': rows},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> fetchHistory(int recordId) async {
    final rows = await client
        .from('purchase_status_items_log')
        .select()
        .eq('record_id', recordId)
        .order('changed_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}
