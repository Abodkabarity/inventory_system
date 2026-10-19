import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../domain/entities/stock_catalog.dart';
import '../../../domain/entities/stock_management.dart';

abstract class StockCatalogDataSource {
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query);
  Future<StockCatalogRegisterBatch> fetchRegisterBatch(int offset) async {
    final page = await fetchPage(StockCatalogQuery(offset: offset, limit: 100));
    return StockCatalogRegisterBatch(
      rows: page.rows,
      total: page.total,
      snapshotAt: page.meta['refreshed_at']?.toString() ?? '',
    );
  }

  Future<StockCatalogItem> fetchItem(String code);
  Future<void> requestRefresh();
  Future<Map<String, dynamic>?> refreshState();
}

class StockCatalogRegisterBatch {
  final List<StockCatalogItem> rows;
  final int total;
  final String snapshotAt;
  const StockCatalogRegisterBatch({
    required this.rows,
    required this.total,
    required this.snapshotAt,
  });
  factory StockCatalogRegisterBatch.fromMap(Map<String, dynamic> map) =>
      StockCatalogRegisterBatch(
        rows: (map['rows'] as List? ?? [])
            .map((r) => StockCatalogItem(stockMap(r)))
            .toList(),
        total: stockNumber(map['total']).toInt(),
        snapshotAt: map['snapshot_at']?.toString() ?? '',
      );
}

extension StockCatalogCompleteRegister on StockCatalogDataSource {
  Future<StockCatalogResult> fetchAll({
    bool Function()? isCancelled,
    void Function(int loaded, int total)? onProgress,
  }) async {
    final overview = await fetchPage(const StockCatalogQuery(limit: 1));
    final rows = <StockCatalogItem>[];
    final codes = <String>{};
    String? version;
    do {
      if (isCancelled?.call() ?? false) {
        throw StateError('Stock load cancelled');
      }
      final batch = await fetchRegisterBatch(rows.length);
      if (isCancelled?.call() ?? false) {
        throw StateError('Stock load cancelled');
      }
      version ??= batch.snapshotAt;
      if (batch.total != overview.total ||
          batch.snapshotAt != version ||
          batch.snapshotAt !=
              (overview.meta['refreshed_at']?.toString() ?? '') ||
          (batch.rows.isEmpty && rows.length < overview.total)) {
        throw StateError(
          'Stock snapshot changed while loading. Please reload.',
        );
      }
      for (final item in batch.rows) {
        if (!codes.add(item.code)) {
          throw StateError(
            'Duplicate product in stock snapshot. Please reload.',
          );
        }
        rows.add(item);
      }
      if (rows.length > overview.total) {
        throw StateError('Inconsistent stock response. Please reload.');
      }
      onProgress?.call(rows.length, overview.total);
    } while (rows.length < overview.total);
    return StockCatalogResult(
      rows: List.unmodifiable(rows),
      summary: overview.summary,
      meta: overview.meta,
      categories: overview.categories,
      suppliers: overview.suppliers,
    );
  }
}

class StockCatalogRemoteDs implements StockCatalogDataSource {
  final SupabaseClient client;
  const StockCatalogRemoteDs(this.client);
  @override
  Future<StockCatalogRegisterBatch> fetchRegisterBatch(int offset) async =>
      StockCatalogRegisterBatch.fromMap(
        stockMap(
          await client.rpc(
            'get_stock_catalog_register_batch',
            params: {'p_offset': offset, 'p_limit': 4000},
          ),
        ),
      );
  @override
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query) async =>
      StockCatalogResult.fromMap(
        stockMap(
          await client.rpc('get_stock_catalog_page', params: query.params),
        ),
      );
  @override
  Future<StockCatalogItem> fetchItem(String code) async {
    final data = await client.rpc(
      'get_stock_catalog_item',
      params: {'p_item_code': code},
    );
    if (data == null) {
      throw StateError('Product no longer available. Reload Overview.');
    }
    return StockCatalogItem(stockMap(data));
  }

  @override
  Future<void> requestRefresh() async {
    await client.rpc('refresh_stock_catalog');
  }

  @override
  Future<Map<String, dynamic>?> refreshState() async => await client
      .from('stock_catalog_refresh_state')
      .select()
      .eq('singleton', true)
      .maybeSingle();
}
