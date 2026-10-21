import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/stock_management_load_config.dart';
import '../../../domain/entities/stock_management.dart';
import 'stock_workspace_memory.dart';

abstract class StockManagementDataSource {
  Future<StockManagementResult> fetchPage(StockManagementQuery query);
  Future<StockManagementRegisterBatch> fetchRegisterBatch(int offset) async {
    final page = await fetchPage(
      StockManagementQuery(
        offset: offset,
        limit: StockManagementLoadConfig.batchSize,
      ),
    );
    return StockManagementRegisterBatch(
      rows: page.rows,
      total: page.total,
      snapshotAt:
          (page.meta['snapshot_at'] ??
                  page.meta['refreshed_at'] ??
                  page.meta['stock_updated_at'])
              ?.toString() ??
          '',
    );
  }

  Future<StockManagementItem> fetchItem(String itemCode);
  Future<void> requestRefresh();
  Future<Map<String, dynamic>?> refreshState();
}

class StockManagementRegisterBatch {
  final List<StockManagementItem> rows;
  final int total;
  final String snapshotAt;
  const StockManagementRegisterBatch({
    required this.rows,
    required this.total,
    required this.snapshotAt,
  });
  factory StockManagementRegisterBatch.fromMap(Map<String, dynamic> map) =>
      StockManagementRegisterBatch(
        rows: (map['rows'] as List? ?? [])
            .map((row) => StockManagementItem(stockMap(row)))
            .toList(),
        total: stockNumber(map['total']).toInt(),
        snapshotAt: map['snapshot_at']?.toString() ?? '',
      );
}

class StockManagementLoadCancelled implements Exception {
  const StockManagementLoadCancelled();
}

extension StockManagementCompleteRegister on StockManagementDataSource {
  Future<StockManagementResult> fetchAll({
    bool Function()? isCancelled,
    void Function(int loaded, int total)? onProgress,
  }) async {
    if (this is StockManagementRemoteDs) {
      final remote = this as StockManagementRemoteDs;
      final result = await remote.memory.read(
        'mrn:register',
        'mrn',
        () => _loadRegister(
          this,
          isCancelled: isCancelled,
          onProgress: onProgress,
        ),
      );
      if (isCancelled?.call() ?? false) {
        throw const StockManagementLoadCancelled();
      }
      onProgress?.call(result.rows.length, result.total);
      return result;
    }
    return _loadRegister(
      this,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  }
}

Future<StockManagementResult> _loadRegister(
  StockManagementDataSource source, {
  bool Function()? isCancelled,
  void Function(int loaded, int total)? onProgress,
}) async {
  final overview = await source.fetchPage(const StockManagementQuery(limit: 1));
  if (isCancelled?.call() ?? false) {
    throw const StockManagementLoadCancelled();
  }
  final rows = <StockManagementItem>[];
  final codes = <String>{};
  String? snapshotAt;
  int? expectedTotal;
  do {
    if (isCancelled?.call() ?? false) {
      throw const StockManagementLoadCancelled();
    }
    final batch = await source.fetchRegisterBatch(rows.length);
    if (isCancelled?.call() ?? false) {
      throw const StockManagementLoadCancelled();
    }
    expectedTotal ??= batch.total;
    snapshotAt ??= batch.snapshotAt;
    if (batch.total != expectedTotal ||
        batch.snapshotAt != snapshotAt ||
        (batch.rows.isEmpty && rows.length < expectedTotal)) {
      throw StateError(
        'The stock register changed while loading. Please refresh.',
      );
    }
    for (final row in batch.rows) {
      if (!codes.add(row.code)) {
        throw StateError(
          'The stock register changed while loading. Please refresh.',
        );
      }
      rows.add(row);
    }
    if (rows.length > expectedTotal) {
      throw StateError('The stock response is inconsistent. Please refresh.');
    }
    onProgress?.call(rows.length, expectedTotal);
  } while (rows.length < expectedTotal);
  if (overview.total != expectedTotal) {
    throw StateError(
      'The stock snapshot changed while loading. Please refresh.',
    );
  }
  final overviewVersion = DateTime.tryParse(
    (overview.meta['snapshot_at'] ?? overview.meta['refreshed_at'])
            ?.toString() ??
        '',
  );
  final batchVersion = DateTime.tryParse(snapshotAt);
  if (overviewVersion != null &&
      batchVersion != null &&
      !overviewVersion.isAtSameMomentAs(batchVersion)) {
    throw StateError(
      'The stock snapshot changed while loading. Please refresh.',
    );
  }
  if (isCancelled?.call() ?? false) {
    throw const StockManagementLoadCancelled();
  }
  return StockManagementResult(
    rows: List.unmodifiable(rows),
    summary: overview.summary,
    meta: overview.meta,
    categories: overview.categories,
    suppliers: overview.suppliers,
  );
}

class StockManagementRemoteDs implements StockManagementDataSource {
  final SupabaseClient client;
  const StockManagementRemoteDs(this.client);
  StockWorkspaceMemory get memory => StockWorkspaceMemory.forClient(client);

  @override
  Future<StockManagementResult> fetchPage(StockManagementQuery query) async {
    final data = await client.rpc(
      'get_stock_management_page',
      params: query.params,
    );
    return StockManagementResult.fromMap(
      Map<String, dynamic>.from(data as Map),
    );
  }

  @override
  Future<StockManagementRegisterBatch> fetchRegisterBatch(int offset) async {
    final data = await client.rpc(
      'get_stock_management_register_batch',
      params: {
        'p_offset': offset,
        'p_limit': StockManagementLoadConfig.batchSize,
      },
    );
    return StockManagementRegisterBatch.fromMap(stockMap(data));
  }

  @override
  Future<StockManagementItem> fetchItem(
    String itemCode,
  ) => memory.read('mrn:detail:$itemCode', 'details', () async {
    dynamic data;
    try {
      data = await client.rpc(
        'get_stock_management_product_details',
        params: {'p_item_code': itemCode},
      );
    } on PostgrestException catch (e) {
      if (!StockWorkspaceMemory.missingRpc(e)) rethrow;
      data = await client.rpc(
        'get_stock_management_item',
        params: {'p_item_code': itemCode},
      );
    }
    if (data == null) {
      throw StateError(
        'This product is no longer in the current snapshot. Refresh the list.',
      );
    }
    final item = StockManagementItem(
      Map<String, dynamic>.unmodifiable(stockMap(data)),
    );
    if (item.code != itemCode) {
      throw StateError('Unexpected product response. Please retry.');
    }
    return item;
  });

  @override
  Future<void> requestRefresh() async {
    memory.clear();
    await client.rpc('refresh_stock_management_snapshot');
  }

  @override
  Future<Map<String, dynamic>?> refreshState() async {
    return await client
        .from('stock_management_refresh_state')
        .select()
        .eq('singleton', true)
        .maybeSingle();
  }
}
