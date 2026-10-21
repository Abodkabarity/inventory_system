import 'package:supabase_flutter/supabase_flutter.dart';

/// Bounded, account-scoped memory. A server revision is checked on every reuse.
class StockWorkspaceMemory {
  static final _clients = Expando<StockWorkspaceMemory>();
  final SupabaseClient client;
  final _saved = <String, (String, Object)>{};
  final _pending = <String, Future<Object>>{};
  String? _session, _discovery;
  int _generation = 0;

  StockWorkspaceMemory._(this.client) {
    _session = client.auth.currentSession?.accessToken;
    client.auth.onAuthStateChange.listen((_) => _synchronize(), onDone: clear);
  }

  static StockWorkspaceMemory forClient(SupabaseClient client) =>
      _clients[client] ??= StockWorkspaceMemory._(client);

  void clear() {
    _generation++;
    _saved.clear();
    _pending.clear();
    _discovery = null;
  }

  void _synchronize() {
    final session = client.auth.currentSession?.accessToken;
    if (session == _session) return;
    _session = session;
    clear();
  }

  void _check(int generation) {
    _synchronize();
    if (generation != _generation) {
      throw StateError('Stock data or account changed. Please retry.');
    }
  }

  static bool missingRpc(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == '42883';

  Future<Map<String, dynamic>> _state() async {
    try {
      final data = await client.rpc('get_stock_workspace_cache_state');
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } on PostgrestException catch (e) {
      if (!missingRpc(e)) rethrow;
      return {}; // Compatibility with servers before the cache migration.
    }
  }

  /// Discover receipts once per changed source or Dubai calendar day, rather
  /// than once per page. A fresh server check still precedes every opening.
  Future<Map<String, dynamic>> prepareExpiry() async {
    _synchronize();
    final generation = _generation;
    Map<String, dynamic> state;
    try {
      final result = await client.rpc(
        'prepare_stock_expiry_workspace',
        params: {'p_known_discovery_version': _discovery},
      );
      state = result is Map ? Map<String, dynamic>.from(result) : {};
    } on PostgrestException catch (e) {
      if (!missingRpc(e)) rethrow;
      await client.rpc('refresh_stock_expiry_watch');
      state = await _state();
    }
    _check(generation);
    _discovery = state['discovery']?.toString();
    return state;
  }

  Future<T> read<T extends Object>(
    String key,
    String revision,
    Future<T> Function() load, {
    Map<String, dynamic>? validatedState,
  }) {
    _synchronize();
    final pending = _pending[key];
    if (pending != null) return pending.then((value) => value as T);
    final generation = _generation;
    late final Future<Object> request;
    request = () async {
      try {
        // Always yield before the finally block can inspect `request`.
        final before = await (validatedState == null
            ? _state()
            : Future.value(validatedState));
        _check(generation);
        final version = before[revision]?.toString();
        final saved = _saved.remove(key);
        if (version != null && version.isNotEmpty && saved?.$1 == version) {
          _saved[key] = saved!;
          return saved.$2;
        }
        final result = await load();
        _check(generation);
        if (version != null && version.isNotEmpty) {
          final after = await _state();
          _check(generation);
          if (after[revision] != version) {
            throw StateError('Stock data changed while loading. Please retry.');
          }
          if (key.contains(':register')) {
            final prefix = '${key.split(':').first}:register';
            _saved.removeWhere((other, _) => other.startsWith(prefix));
          }
          _saved[key] = (version, result);
          while (_saved.length > 28) {
            _saved.remove(_saved.keys.first);
          }
        }
        return result;
      } finally {
        if (identical(_pending[key], request)) _pending.remove(key);
      }
    }();
    _pending[key] = request;
    return request.then((value) => value as T);
  }
}
