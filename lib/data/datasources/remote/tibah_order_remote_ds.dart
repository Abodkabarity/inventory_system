import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/data_batch_config.dart';
import '../../../domain/entities/store_order_item.dart';
import '../../../domain/entities/tibah_order.dart';

class TibahOrderRemoteDs {
  TibahOrderRemoteDs(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> _call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async => Map<String, dynamic>.from(
    await client.rpc(
      'tibah_max_order',
      params: {'p_action': action, 'p_payload': payload},
    ),
  );

  Future<TibahOrder?> current(TibahOrderType type) async {
    final data = await _call('current', {'order_type': type.label});
    return data['upload'] == null
        ? null
        : TibahOrder.fromJson(Map<String, dynamic>.from(data['upload']));
  }

  Future<List<TibahOrder>> currentOrders() async {
    final data = await _call('current');
    return List<Map<String, dynamic>>.from(
      data['uploads'],
    ).map(TibahOrder.fromJson).toList();
  }

  Future<void> replace({
    required TibahOrderType type,
    required String fileName,
    required List<Map<String, dynamic>> rows,
    void Function(int completed, int total)? onProgress,
  }) => replaceFromFile(
    type: type,
    fileName: fileName,
    readRows: () async => rows,
    onProgress: onProgress,
  );

  /// Clear in a separate committed request BEFORE decoding/validating the file.
  /// A failed read/stage never restores old Max or clears a newer upload.
  Future<void> replaceFromFile({
    required TibahOrderType type,
    required String fileName,
    required Future<List<Map<String, dynamic>>> Function() readRows,
    void Function()? onCleared,
    void Function(int completed, int total)? onProgress,
  }) async {
    final started = await _call('begin', {
      'order_type': type.label,
      'file_name': fileName,
    });
    final id = started['id'] as String;
    onCleared?.call();
    final rows = await readRows();
    await _call('configure', {'id': id, 'total': rows.length});
    // Never automatically retry a write: a timed out commit may have succeeded.
    for (
      var offset = 0;
      offset < rows.length;
      offset += DataBatchConfig.batchSize
    ) {
      final end = (offset + DataBatchConfig.batchSize).clamp(0, rows.length);
      final staged = await _call('stage', {
        'id': id,
        'rows': rows.sublist(offset, end),
      });
      if (staged['received'] != end) {
        throw StateError(
          'Incomplete upload. Previous Max was cleared. Refresh before trying again.',
        );
      }
      onProgress?.call(end, rows.length);
    }
    await _call('commit', {'id': id});
  }

  Future<void> complete(String id) async {
    await _call('complete', {'id': id});
  }

  Future<List<StoreOrderItem>> items(TibahOrder order) async {
    final result = <StoreOrderItem>[];
    final codes = <String>{};
    var after = '';
    while (codes.length < order.total) {
      final data = await _call('items', {
        'id': order.id,
        'after': after,
        'limit': DataBatchConfig.batchSize,
      });
      final rows = List<Map<String, dynamic>>.from(data['rows']);
      if (data['id'] != order.id ||
          data['total'] != order.total ||
          rows.isEmpty) {
        throw StateError(
          'The order changed or is incomplete. Refresh the order.',
        );
      }
      for (final row in rows) {
        final code = row['item_code'] as String;
        if (code.compareTo(after) <= 0 || !codes.add(code)) {
          throw StateError('Invalid order snapshot. Refresh the order.');
        }
        after = code;
        final qty =
            num.tryParse(
              row['final_reorder_qty_store_stock_gt_0']?.toString() ?? '',
            ) ??
            0;
        if (qty > 0) {
          result.add(
            StoreOrderItem(
              itemCode: code,
              itemName: row['item_name']?.toString() ?? '',
              barcode: row['barcode']?.toString() ?? '',
              supplier: row['supplier']?.toString() ?? '',
              classification:
                  row['store_item_classifications']?.toString() ?? '',
              category: row['category']?.toString() ?? '',
              quantity: qty,
            ),
          );
        }
      }
      if (codes.length > order.total) {
        throw StateError('Invalid order row count.');
      }
    }
    // A replacement or completion during pagination invalidates the loaded view.
    final latest = await current(order.type);
    if (latest?.id != order.id || latest?.isReady != true) {
      throw StateError(
        'This order has been replaced or completed. Refresh the order.',
      );
    }
    return result;
  }
}
