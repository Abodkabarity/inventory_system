import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/stock_management_load_config.dart';
import '../../../domain/entities/stock_expiry.dart';
import '../../../domain/entities/stock_management.dart';
import 'stock_workspace_memory.dart';

abstract class StockExpiryDataSource {
  Future<StockExpiryResult> fetchPage(StockExpiryQuery query);
  Future<StockExpiryAlert> fetchItem(StockExpiryAlert alert);
  Future<Map<String, dynamic>> save(
    StockExpiryAlert alert, {
    required String note,
    required String action,
  });
}

/// Assemble every shared-size batch before exposing a result so
/// Excel-style column filters never silently operate on an incomplete register.
extension StockExpiryCompleteRegister on StockExpiryDataSource {
  Future<StockExpiryResult> fetchAll(
    StockExpiryQuery query, {
    bool Function()? isCancelled,
    void Function(int loaded, int total)? onProgress,
  }) async {
    if (this is StockExpiryRemoteDs) {
      final remote = this as StockExpiryRemoteDs;
      final state = await remote.memory.prepareExpiry();
      final key =
          'expiry:register:${query.search}:${query.reviewState}:${query.urgency}';
      final result = await remote.memory.read(
        key,
        'expiry',
        () => _loadExpiryRegister(
          remote._fetchPage,
          query,
          isCancelled: isCancelled,
          onProgress: onProgress,
        ),
        validatedState: state,
      );
      if (isCancelled?.call() ?? false) throw const StockExpiryLoadCancelled();
      onProgress?.call(result.rows.length, result.total);
      return result;
    }
    return _loadExpiryRegister(
      fetchPage,
      query,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  }
}

Future<StockExpiryResult> _loadExpiryRegister(
  Future<StockExpiryResult> Function(StockExpiryQuery) fetchPage,
  StockExpiryQuery query, {
  bool Function()? isCancelled,
  void Function(int loaded, int total)? onProgress,
}) async {
  final rows = <StockExpiryAlert>[];
  final keys = <String>{};
  StockExpiryResult? first;
  do {
    if (isCancelled?.call() ?? false) throw const StockExpiryLoadCancelled();
    final batch = await fetchPage(
      StockExpiryQuery(
        search: query.search,
        reviewState: query.reviewState,
        urgency: query.urgency,
        offset: rows.length,
        limit: StockManagementLoadConfig.batchSize,
      ),
    );
    if (isCancelled?.call() ?? false) throw const StockExpiryLoadCancelled();
    first ??= batch;
    if (batch.total != first.total ||
        (batch.rows.isEmpty && rows.length < first.total)) {
      throw StateError(
        'The expiry register changed while loading. Please refresh.',
      );
    }
    for (final row in batch.rows) {
      if (!keys.add(row.key)) {
        throw StateError(
          'The expiry register changed while loading. Please refresh.',
        );
      }
      rows.add(row);
    }
    if (rows.length > first.total) {
      throw StateError('The expiry response is inconsistent. Please refresh.');
    }
    onProgress?.call(rows.length, first.total);
  } while (rows.length < first.total);
  if (isCancelled?.call() ?? false) throw const StockExpiryLoadCancelled();
  return StockExpiryResult(
    rows: List.unmodifiable(rows),
    total: first.total,
    summary: first.summary,
    meta: first.meta,
  );
}

class StockExpiryLoadCancelled implements Exception {
  const StockExpiryLoadCancelled();
}

class StockExpiryRemoteDs implements StockExpiryDataSource {
  final SupabaseClient client;
  const StockExpiryRemoteDs(this.client);
  StockWorkspaceMemory get memory => StockWorkspaceMemory.forClient(client);
  @override
  Future<StockExpiryResult> fetchPage(StockExpiryQuery query) async {
    await client.rpc('refresh_stock_expiry_watch');
    return _fetchPage(query);
  }

  Future<StockExpiryResult> _fetchPage(StockExpiryQuery query) async =>
      StockExpiryResult.fromMap(
        stockMap(
          await client.rpc('get_stock_expiry_page', params: query.params),
        ),
      );

  @override
  Future<StockExpiryAlert> fetchItem(StockExpiryAlert alert) => memory.read(
    'expiry:detail:${alert.key}',
    'expiry',
    () async {
      final data = await client.rpc(
        'get_stock_expiry_item',
        params: {
          'p_item_code': alert.code,
          'p_expiry_date': alert.expiry,
          'p_mrn_date': alert.mrnDate,
        },
      );
      if (data == null) {
        throw StateError('This alert is no longer eligible. Reload the list.');
      }
      final result = StockExpiryAlert(
        Map<String, dynamic>.unmodifiable(stockMap(data)),
      );
      if (result.key != alert.key) {
        throw StateError('Unexpected expiry response. Please retry.');
      }
      return result;
    },
  );

  @override
  Future<Map<String, dynamic>> save(
    StockExpiryAlert alert, {
    required String note,
    required String action,
  }) async {
    // Clear before dispatch: failures and in-flight reads cannot restore old notes.
    memory.clear();
    return stockMap(
      await client.rpc(
        'save_stock_expiry_review',
        params: {
          'p_item_code': alert.code,
          'p_expiry_date': alert.expiry,
          'p_mrn_date': alert.mrnDate,
          'p_fingerprint': alert.text('receipt_fingerprint'),
          'p_note': note,
          'p_action': action,
          'p_expected_updated_at': alert.reviewVersion,
        },
      ),
    );
  }
}
