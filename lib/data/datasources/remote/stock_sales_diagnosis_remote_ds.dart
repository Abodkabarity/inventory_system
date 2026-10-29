import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/stock_management.dart';
import '../../../domain/entities/stock_sales_diagnosis.dart';

/// Separate from the product loader: analysis never delays charts or receipts.
/// Bounded per-client memory, short freshness window, auth-scoped coalescing.
class StockSalesDiagnosisRemoteDs {
  static final _instances = Expando<StockSalesDiagnosisRemoteDs>();
  final SupabaseClient client;
  final _saved = <String, (DateTime, StockSalesDiagnosis)>{};
  final _pending = <String, Future<StockSalesDiagnosis>>{};
  String? _token;
  StockSalesDiagnosisRemoteDs._(this.client);
  factory StockSalesDiagnosisRemoteDs(SupabaseClient client) =>
      _instances[client] ??= StockSalesDiagnosisRemoteDs._(client);

  Future<StockSalesDiagnosis> fetch(String code, {bool refresh = false}) {
    final token = client.auth.currentSession?.accessToken;
    if (_token != token) {
      _saved.clear();
      _pending.clear();
      _token = token;
    }
    if (refresh) _saved.remove(code);
    final saved = _saved[code];
    if (saved != null &&
        DateTime.now().difference(saved.$1) < const Duration(minutes: 2)) {
      return Future.value(saved.$2);
    }
    if (_pending[code] case final pending?) return pending;
    late final Future<StockSalesDiagnosis> request;
    request = () async {
      try {
        final raw = stockMap(
          await client.rpc(
            'get_stock_network_sales_evidence',
            params: {'p_item_code': code},
          ),
        );
        if (client.auth.currentSession?.accessToken != token) {
          throw StateError('Account changed. Reopen the product.');
        }
        if (raw['status'] != 'ready') {
          throw StateError('Daily sales and stock are not ready.');
        }
        final result = StockSalesDiagnosis.fromMap(raw);
        _saved.remove(code);
        _saved[code] = (DateTime.now(), result);
        while (_saved.length > 32) {
          _saved.remove(_saved.keys.first);
        }
        return result;
      } finally {
        if (identical(_pending[code], request)) _pending.remove(code);
      }
    }();
    _pending[code] = request;
    return request;
  }
}
