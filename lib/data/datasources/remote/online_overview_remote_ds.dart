import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/online_overview_local_config.dart';
import '../../../domain/entities/online_overview.dart';
import '../../../domain/entities/stock_management.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../domain/entities/stock_catalog.dart';

abstract class OnlineOverviewDataSource {
  Future<OnlineOverviewSnapshot> load({
    String branch = '',
    OnlineSalesScope scope = OnlineSalesScope.onlineOnly,
    bool Function()? isCancelled,
    void Function(String message)? onProgress,
  });
  Future<void> requestRefresh();
  Future<Map<String, dynamic>> refreshState();
  Future<Map<String, dynamic>> branchAvailability({required String generation});
  Future<Map<String, dynamic>> forecastDetails(
    String code, {
    required String generation,
  });
  Future<OnlineProductAudit> audit(String code, {required String generation});
  Future<Map<String, dynamic>> recentOnlineSales(
    String code, {
    required String generation,
    required String branch,
  });
  Future<List<Map<String, dynamic>>> monthlyOnlineSales(
    String code, {
    required String generation,
    required String branch,
  });
  Future<List<Map<String, dynamic>>> stockBreakdown(
    String code, {
    String? generation,
  }) async => const [];
}

class OnlineSourcePage {
  final List<Map<String, dynamic>> rows;
  final int total;
  const OnlineSourcePage(this.rows, this.total);
}

typedef _OnlinePageResult = ({
  OnlineSourcePage? page,
  Object? error,
  StackTrace? stack,
});

/// Advances by the actual response size, including servers with a smaller cap.
/// Exact counts and unique keys are mandatory; never silently use a partial set.
Future<List<Map<String, dynamic>>> loadOnlineSource({
  required Future<OnlineSourcePage> Function(int offset, int limit) fetch,
  required String Function(Map<String, dynamic>) identity,
  bool Function()? isCancelled,
  void Function(int loaded, int total)? onProgress,
  int? expectedTotal,
}) async {
  final rows = <Map<String, dynamic>>[];
  final keys = <String>{};
  int? total;
  final pending = <int, Future<_OnlinePageResult>>{};
  void prefetch(int offset) {
    if (expectedTotal == null ||
        offset >= expectedTotal ||
        (isCancelled?.call() ?? false)) {
      return;
    }
    pending.putIfAbsent(offset, () async {
      try {
        return (
          page: await fetch(offset, OnlineOverviewLocalConfig.batchSize),
          error: null,
          stack: null,
        );
      } catch (error, stack) {
        return (page: null, error: error, stack: stack);
      }
    });
  }

  // Metadata supplies exact counts. Keep at most two requests in flight;
  // consumption still follows actual row counts if the server has a lower cap.
  prefetch(0);
  prefetch(OnlineOverviewLocalConfig.batchSize);
  do {
    if (isCancelled?.call() ?? false) {
      throw StateError('Online load cancelled.');
    }
    final waiting = pending.remove(rows.length);
    final result = waiting == null ? null : await waiting;
    if (result?.error != null) {
      Error.throwWithStackTrace(result!.error!, result.stack!);
    }
    final page =
        result?.page ??
        await fetch(rows.length, OnlineOverviewLocalConfig.batchSize);
    if (isCancelled?.call() ?? false) {
      throw StateError('Online load cancelled.');
    }
    total ??= page.total;
    if ((expectedTotal != null && page.total != expectedTotal) ||
        page.total != total ||
        (page.rows.isEmpty && rows.length < total)) {
      throw StateError(
        'Source changed or is incomplete. Reload Online Overview.',
      );
    }
    for (final row in page.rows) {
      final key = identity(row);
      if (key.isEmpty || !keys.add(key)) {
        throw StateError(
          'Duplicate or missing source identity. Reload Online Overview.',
        );
      }
      rows.add(row);
    }
    if (rows.length > total) throw StateError('Inconsistent source row count.');
    onProgress?.call(rows.length, total);
    if (page.rows.length == OnlineOverviewLocalConfig.batchSize &&
        pending.length < 2) {
      prefetch(rows.length);
      if (pending.length < 2) {
        prefetch(rows.length + OnlineOverviewLocalConfig.batchSize);
      }
    }
  } while (rows.length < total);
  return rows;
}

class OnlineSnapshotNotReady implements Exception {
  final String status;
  const OnlineSnapshotNotReady(this.status);
  @override
  String toString() => 'The first Online Overview result is being prepared.';
}

/// Reads only the completed server register. No raw sales/catalog/status scans.
class OnlineOverviewRemoteDs implements OnlineOverviewDataSource {
  final SupabaseClient client;
  final bool preview;
  final _saved = <String, OnlineOverviewSnapshot>{};
  String? _session;
  OnlineOverviewRemoteDs(this.client, {this.preview = false});

  Future<dynamic> _rpc(String name, {Map<String, dynamic>? params}) {
    if (!preview) return client.rpc(name, params: params);
    final action = const {
      'get_local_online_overview_state': 'state',
      'get_local_online_overview_batch': 'batch',
      'get_local_online_overview_stock': 'stock',
      'get_local_online_overview_monthly_sales': 'monthly_sales',
      'get_local_online_overview_recent_sales': 'recent_sales',
      'get_local_online_overview_forecast': 'forecast',
      'get_local_online_overview_availability': 'availability',
      'refresh_local_online_overview': 'refresh',
    }[name];
    if (action == null) throw StateError('Unknown Online Overview request.');
    return client.rpc(
      'get_local_online_overview_preview',
      params: {'p_action': action, ...?params},
    );
  }

  @override
  Future<Map<String, dynamic>> forecastDetails(
    String code, {
    required String generation,
  }) async => stockMap(
    await _rpc(
      'get_local_online_overview_forecast',
      params: {'p_generation': generation, 'p_item_code': code},
    ),
  );

  @override
  Future<Map<String, dynamic>> recentOnlineSales(
    String code, {
    required String generation,
    required String branch,
  }) async => stockMap(
    await _rpc(
      'get_local_online_overview_recent_sales',
      params: {
        'p_generation': generation,
        'p_item_code': code,
        'p_branch': branch,
      },
    ),
  );

  @override
  Future<List<Map<String, dynamic>>> monthlyOnlineSales(
    String code, {
    required String generation,
    required String branch,
  }) async {
    final raw = await _rpc(
      'get_local_online_overview_monthly_sales',
      params: {
        'p_generation': generation,
        'p_item_code': code,
        'p_branch': branch,
      },
    );
    return (raw as List).map(stockMap).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> stockBreakdown(
    String code, {
    String? generation,
  }) async {
    final token = generation ?? (await refreshState())['generation'];
    final raw = await _rpc(
      'get_local_online_overview_stock',
      params: {'p_generation': token, 'p_item_code': code},
    );
    return (raw as List? ?? []).map(stockMap).toList();
  }

  @override
  Future<Map<String, dynamic>> refreshState() async =>
      stockMap(await _rpc('get_local_online_overview_state'));
  @override
  Future<Map<String, dynamic>> branchAvailability({
    required String generation,
  }) async => stockMap(
    await _rpc(
      'get_local_online_overview_availability',
      params: {'p_generation': generation},
    ),
  );
  @override
  Future<void> requestRefresh() async {
    await _rpc('refresh_local_online_overview');
  }

  @override
  Future<OnlineOverviewSnapshot> load({
    String branch = '',
    OnlineSalesScope scope = OnlineSalesScope.onlineOnly,
    bool Function()? isCancelled,
    void Function(String message)? onProgress,
  }) async {
    if (scope != OnlineSalesScope.onlineOnly) {
      throw ArgumentError.value(
        scope,
        'scope',
        'Only online sales are available',
      );
    }
    final session = client.auth.currentSession?.accessToken;
    if (_session != session) {
      _saved.clear();
      _session = session;
    }
    void check() {
      if ((isCancelled?.call() ?? false) ||
          client.auth.currentSession?.accessToken != session) {
        throw StateError('Session or page changed. Reload Online Overview.');
      }
    }

    onProgress?.call('Loading products…');
    final state = await refreshState();
    check();
    if (state['status'] == 'needs_update') {
      throw StateError('The local sales preview needs an update.');
    }
    final generation = '${state['generation'] ?? ''}';
    if (generation.isEmpty) throw OnlineSnapshotNotReady('${state['status']}');
    final meta = stockMap(state['meta']);
    final branches = (meta['branches'] as List? ?? []).map((raw) {
      final row = stockMap(raw);
      return OnlineBranch('${row['name']}', '${row['group'] ?? ''}');
    }).toList();
    final registry = StoreBranchIdentityRegistry.groups;
    final groups = {
      for (final branch in branches) onlineKey(branch.name): branch.group,
    };
    if (groups.entries.any(
      (entry) => registry.value[entry.key] != entry.value,
    )) {
      registry.value = Map.unmodifiable({...registry.value, ...groups});
    }
    final selected = branches
        .where((b) => branch.isEmpty || b.name == branch)
        .map((b) => b.name)
        .toList();
    if (selected.isEmpty) {
      throw StateError('Online branch is no longer active. Reload.');
    }
    final cacheKey = '$generation\u0000$branch\u0000${scope.name}';
    final cached = _saved[cacheKey];
    if (cached != null) return cached;
    final raw = await loadOnlineSource(
      fetch: (offset, limit) async {
        final page = stockMap(
          await _rpc(
            'get_local_online_overview_batch',
            params: {
              'p_generation': generation,
              'p_branch': branch,
              'p_scope': scope.name,
              'p_offset': offset,
              'p_limit': limit,
            },
          ),
        );
        check();
        if (page['generation'] != generation ||
            stockNumber(page['total']) != stockNumber(meta['items'])) {
          throw StateError('Prepared online snapshot changed. Reload.');
        }
        return OnlineSourcePage(
          (page['rows'] as List? ?? []).map(stockMap).toList(),
          stockNumber(page['total']).toInt(),
        );
      },
      identity: (row) => '${row['code'] ?? ''}',
      expectedTotal: stockNumber(meta['items']).toInt(),
      isCancelled: isCancelled,
      onProgress: (loaded, total) =>
          onProgress?.call('Loading products · $loaded of $total'),
    );
    final after = await refreshState();
    check();
    if (after['generation'] != generation) {
      throw StateError('Prepared online snapshot changed. Reload.');
    }
    final rows = raw
        .map((row) => OnlineOverviewRow.fromPreparedMap(row, selected))
        .toList();
    final snapshot = OnlineOverviewSnapshot(
      catalog: StockCatalogResult(
        rows: rows.map((row) => row.item).toList(),
        summary: {'items': rows.length},
        meta: meta,
      ),
      branches: branches,
      sales: const [],
      loadedAt:
          DateTime.tryParse('${meta['refreshed_at']}') ??
          DateTime.now().toUtc(),
      purchaseStatuses: {
        for (final row in rows) row.item.code: row.purchaseStatus,
      },
      preparedRows: List.unmodifiable(rows),
      generation: generation,
      refreshStatus: '${after['status']}',
      serverMeta: meta,
    );
    _saved.removeWhere((key, _) => !key.startsWith('$generation\u0000'));
    if (_saved.length >= 4) _saved.remove(_saved.keys.first);
    _saved[cacheKey] = snapshot;
    return snapshot;
  }

  @override
  Future<OnlineProductAudit> audit(
    String code, {
    required String generation,
  }) async {
    final session = client.auth.currentSession?.accessToken;
    final rows = await stockBreakdown(code, generation: generation);
    if (session != client.auth.currentSession?.accessToken) {
      throw StateError('Session changed. Recheck stock history.');
    }
    final through = DateTime.tryParse(
      '${rows.firstOrNull?['history_through']}',
    );
    if (through == null) throw StateError('Stock history is not ready.');
    return OnlineProductAudit(
      through: through,
      branches: {
        for (final row in rows)
          onlineKey('${row['branch_name']}'): OnlineBranchAudit(
            branch: '${row['branch_name']}',
            through: through,
            verified: row['stocked_days'] is num,
            stockedDays: stockNumber(row['stocked_days']).toInt(),
            currentStock: (row['stock'] as num?)?.toDouble(),
          ),
      },
    );
  }
}
