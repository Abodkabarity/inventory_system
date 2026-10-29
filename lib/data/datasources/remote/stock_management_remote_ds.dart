import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/stock_management_load_config.dart';
import '../../../domain/entities/stock_management.dart';
import '../../../domain/entities/stock_mrn_receipt_history.dart';
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
  Future<StockMrnReceiptHistory> fetchReceiptHistory(String itemCode) {
    final source = this;
    if (source is StockManagementRemoteDs) {
      return source.fetchReceiptHistory(itemCode);
    }
    return Future.error(UnsupportedError('Receipt history is unavailable.'));
  }

  Future<StockManagementResult> fetchAll({
    bool Function()? isCancelled,
    void Function(int loaded, int total)? onProgress,
  }) async {
    if (this is StockManagementRemoteDs) {
      final remote = this as StockManagementRemoteDs;
      final result = await remote.memory.read(
        '${remote.namespace}:register',
        remote.namespace,
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
      if (!codes.add(row.registerKey)) {
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
  if (overview.meta['source'] == 'mrn_cd_apg_2026' &&
      overview.meta['snapshot_at'] != snapshotAt) {
    throw StateError('The MRN CD data changed while loading. Please refresh.');
  }
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
  final bool cd;
  final String? warehouse;
  const StockManagementRemoteDs(this.client, {this.cd = false, this.warehouse});
  String get namespace => cd ? 'mrn_cd' : 'mrn';
  String get _rpc => cd ? 'get_stock_mrn_cd' : 'get_stock_management';
  StockManagementRemoteDs forReceipt(StockManagementItem item) => cd
      ? StockManagementRemoteDs(client, cd: true, warehouse: item.warehouse)
      : this;
  StockWorkspaceMemory get memory => StockWorkspaceMemory.forClient(client);

  @override
  Future<StockManagementResult> fetchPage(StockManagementQuery query) async {
    final data = await client.rpc('${_rpc}_page', params: query.params);
    return StockManagementResult.fromMap(
      Map<String, dynamic>.from(data as Map),
    );
  }

  @override
  Future<StockManagementRegisterBatch> fetchRegisterBatch(int offset) async {
    final data = await client.rpc(
      '${_rpc}_register_batch',
      params: {
        'p_offset': offset,
        'p_limit': StockManagementLoadConfig.batchSize,
      },
    );
    return StockManagementRegisterBatch.fromMap(stockMap(data));
  }

  @override
  Future<StockManagementItem> fetchItem(String itemCode) => memory.read(
    '$namespace:detail:$warehouse:$itemCode',
    cd ? namespace : 'details',
    () async {
      dynamic data;
      if (cd) {
        if (warehouse == null || warehouse!.isEmpty) {
          throw StateError('Choose a receiving warehouse.');
        }
        data = await client.rpc(
          '${_rpc}_item',
          params: {'p_item_code': itemCode, 'p_warehouse': warehouse},
        );
      } else {
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
      if (cd && item.warehouse != warehouse) {
        throw StateError('Unexpected warehouse response. Please retry.');
      }
      return item;
    },
  );

  Future<StockMrnReceiptHistory> fetchReceiptHistory(String itemCode) =>
      memory.read(
        '$namespace:receipt-history:$warehouse:$itemCode',
        cd ? namespace : 'details',
        () async {
          final lines = <Map<String, dynamic>>[];
          final identities = <String>{};
          Map<String, dynamic>? meta;
          int? total;
          String? version;
          do {
            final page = stockMap(
              await client.rpc(
                '${_rpc}_receipt_history',
                params: {
                  'p_item_code': itemCode,
                  if (cd) 'p_warehouse': warehouse,
                  'p_offset': lines.length,
                  'p_limit': StockManagementLoadConfig.batchSize,
                },
              ),
            );
            final rows = (page['rows'] as List? ?? []).map(stockMap).toList();
            total ??= stockNumber(page['total']).toInt();
            version ??= page['snapshot_version']?.toString() ?? '';
            meta ??= page;
            if (page['item_code'] != itemCode ||
                (cd && page['warehouse'] != warehouse) ||
                version.isEmpty ||
                page['snapshot_version'] != version ||
                stockNumber(page['total']).toInt() != total ||
                (rows.isEmpty && lines.length < total)) {
              throw StateError(
                'Receipt history changed while loading. Please retry.',
              );
            }
            for (final row in rows) {
              final id = row['line_id']?.toString() ?? '';
              if (id.isEmpty || !identities.add(id)) {
                throw StateError(
                  'Receipt history is inconsistent. Please retry.',
                );
              }
              lines.add(Map.unmodifiable(row));
            }
            if (lines.length > total) {
              throw StateError('Receipt history is incomplete. Please retry.');
            }
          } while (lines.length < total);
          return StockMrnReceiptHistory(
            lines: List.unmodifiable(lines),
            mrnCount: stockNumber(meta['mrn_count']).toInt(),
            dayCount: stockNumber(meta['day_count']).toInt(),
            receivedQty: stockNumber(meta['total_qty'] ?? meta['received_qty']),
            bonus: stockNumber(meta['bonus']),
            from: meta['from']?.toString() ?? '',
            through: meta['through']?.toString() ?? '',
          );
        },
      );

  @override
  Future<void> requestRefresh() async {
    memory.clear();
    if (cd) return;
    await client.rpc('refresh_stock_management_snapshot');
  }

  @override
  Future<Map<String, dynamic>?> refreshState() async {
    if (cd) return stockMap(await client.rpc('${_rpc}_refresh_state'));
    return await client
        .from('stock_management_refresh_state')
        .select()
        .eq('singleton', true)
        .maybeSingle();
  }
}
