import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/stock_management_load_config.dart';
import '../../../domain/entities/stock_catalog.dart';
import '../../../domain/entities/stock_management.dart';
import 'stock_catalog_memory_cache.dart';

abstract class StockCatalogDataSource {
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query);
  Future<StockCatalogRegisterBatch> fetchRegisterBatch(int offset) async {
    final page = await fetchPage(
      StockCatalogQuery(
        offset: offset,
        limit: StockManagementLoadConfig.batchSize,
      ),
    );
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
    final remote = this is StockCatalogRemoteDs
        ? this as StockCatalogRemoteDs
        : null;
    final generation = remote?._memory.generation;
    final overview = await fetchPage(const StockCatalogQuery(limit: 1));
    if (isCancelled?.call() ?? false) throw StateError('Stock load cancelled');
    if (remote != null) {
      remote._memory.checkGeneration(generation!);
      final cached = remote._memory.reuseRegister(overview);
      if (cached != null) {
        onProgress?.call(cached.rows.length, cached.total);
        return cached;
      }
    }
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
    final result = StockCatalogResult(
      rows: List.unmodifiable(rows),
      summary: overview.summary,
      meta: overview.meta,
      categories: overview.categories,
      suppliers: overview.suppliers,
    );
    remote?._memory.rememberRegister(result, generation!);
    return result;
  }
}

class _CatalogClientMemory {
  final cache = StockCatalogMemoryCache();
  String? _scope;
  _CatalogClientMemory(this._scope);
  void synchronize(String? scope) {
    if (scope == _scope) return;
    _scope = scope;
    cache.clear();
  }
}

class StockCatalogRemoteDs implements StockCatalogDataSource {
  static final _memories = Expando<_CatalogClientMemory>();
  final SupabaseClient client;
  const StockCatalogRemoteDs(this.client);
  StockCatalogMemoryCache get _memory {
    final existing = _memories[client];
    if (existing != null) {
      existing.synchronize(client.auth.currentSession?.accessToken);
      return existing.cache;
    }
    final memory = _CatalogClientMemory(
      client.auth.currentSession?.accessToken,
    );
    _memories[client] = memory;
    client.auth.onAuthStateChange.listen(
      // Auth notifications may be queued. Compare the current session rather
      // than invalidating a new request for an already-handled login event.
      (_) => memory.synchronize(client.auth.currentSession?.accessToken),
      onDone: memory.cache.clear,
    );
    return memory.cache;
  }

  @override
  Future<StockCatalogRegisterBatch> fetchRegisterBatch(int offset) async =>
      StockCatalogRegisterBatch.fromMap(
        stockMap(
          await client.rpc(
            'get_stock_catalog_register_batch',
            params: {
              'p_offset': offset,
              'p_limit': StockManagementLoadConfig.batchSize,
            },
          ),
        ),
      );
  @override
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query) async {
    try {
      return StockCatalogResult.fromMap(
        stockMap(
          await client.rpc('get_stock_catalog_page', params: query.params),
        ),
      );
    } catch (_) {
      _memory.clear();
      rethrow;
    }
  }

  @override
  Future<StockCatalogItem> fetchItem(String code) =>
      _memory.item(code, (version) async {
        dynamic data;
        if (version != null) {
          try {
            data = await client.rpc(
              'get_stock_catalog_item_if_changed',
              params: {'p_item_code': code, 'p_known_version': version},
            );
            return data == null ? null : stockMap(data);
          } on PostgrestException catch (error) {
            // Rolling back the server must remain compatible with open clients.
            if (error.code != 'PGRST202' && error.code != '42883') rethrow;
          }
        }
        data = await client.rpc(
          'get_stock_catalog_item',
          params: {'p_item_code': code},
        );
        return data == null ? null : stockMap(data);
      });

  @override
  Future<void> requestRefresh() async {
    _memory.clear();
    await client.rpc('refresh_stock_catalog');
  }

  @override
  Future<Map<String, dynamic>?> refreshState() async => await client
      .from('stock_catalog_refresh_state')
      .select()
      .eq('singleton', true)
      .maybeSingle();
}
