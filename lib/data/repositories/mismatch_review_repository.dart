import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/stock_management_load_config.dart';
import '../../core/utils/store_branch_identity_registry.dart';
import '../../domain/entities/mismatch_review.dart';

class MismatchReviewSnapshot {
  const MismatchReviewSnapshot(
    this.rows,
    this.coverage,
    this.sourceVersion, [
    this.token = '',
  ]);
  final List<MismatchReview> rows;
  final List<Map<String, dynamic>> coverage;
  final String sourceVersion;
  final String token;
}

class MismatchReviewChanges {
  const MismatchReviewChanges(this.rows, this.sourceVersion, this.token);
  final List<MismatchReview> rows;
  final String sourceVersion, token;
}

abstract class MismatchReviewRepository {
  Future<MismatchReviewSnapshot> load();
  Future<Map<String, dynamic>?> detail(int id);
  Future<void> refreshReviews(List<int> ids);
  Future<MismatchReviewChanges?> changes(List<int> ids) async => null;
  void watch(
    void Function(int? id) changed,
    void Function(bool live) connection,
  );
  Future<void> close();
}

class SupabaseMismatchReviewRepository implements MismatchReviewRepository {
  SupabaseMismatchReviewRepository(this.client);
  final SupabaseClient client;
  RealtimeChannel? _channel;

  @override
  Future<MismatchReviewSnapshot> load() async {
    await StoreBranchIdentityRegistry.load(client);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final rows = <MismatchReview>[];
        final ids = <int>{};
        String? token;
        String? source;
        var after = 0;
        var total = 0;
        var coverage = <Map<String, dynamic>>[];
        while (true) {
          final page = Map<String, dynamic>.from(
            await client.rpc(
                  'inventory_mismatch_review_page',
                  params: {
                    'p_after': after,
                    'p_limit': StockManagementLoadConfig.batchSize,
                    'p_snapshot': token,
                  },
                )
                as Map,
          );
          token ??= '${page['snapshot']}';
          source ??= '${page['source_version']}';
          if (token != '${page['snapshot']}' ||
              source != '${page['source_version']}') {
            throw const FormatException(
              'Review snapshot changed during loading',
            );
          }
          total = (page['total'] as num).toInt();
          final part = (page['rows'] as List)
              .map((r) => MismatchReview(Map<String, dynamic>.from(r as Map)))
              .toList();
          for (final row in part) {
            if (!ids.add(row.id)) {
              throw const FormatException('Duplicate review identity');
            }
          }
          rows.addAll(part);
          coverage = (page['coverage'] as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
          if (page['has_more'] != true) break;
          final next = (page['next_after'] as num).toInt();
          if (part.isEmpty || next <= after) {
            throw const FormatException('Incomplete review page');
          }
          after = next;
        }
        if (rows.length != total) {
          throw const FormatException('Review count does not match snapshot');
        }
        return MismatchReviewSnapshot(rows, coverage, source, token);
      } on PostgrestException catch (e) {
        if (e.code != '40001' || attempt == 2) rethrow;
      } on FormatException {
        if (attempt == 2) rethrow;
      }
    }
    throw StateError(
      'Mismatch entries changed repeatedly. Refresh the report.',
    );
  }

  @override
  Future<Map<String, dynamic>?> detail(int id) async {
    final result = await client.rpc(
      'inventory_mismatch_review_detail',
      params: {'p_id': id},
    );
    return result == null ? null : Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<void> refreshReviews(List<int> ids) async {
    if (ids.isNotEmpty) {
      await client.rpc(
        'inventory_refresh_mismatch_reviews',
        params: {'p_ids': ids},
      );
    }
  }

  @override
  Future<MismatchReviewChanges?> changes(List<int> ids) async {
    final result = Map<String, dynamic>.from(
      await client.rpc(
            'inventory_mismatch_review_changes',
            params: {'p_ids': ids},
          )
          as Map,
    );
    final rows = (result['rows'] as List)
        .map((r) => MismatchReview(Map<String, dynamic>.from(r as Map)))
        .toList();
    final returned = rows.map((r) => r.id).toSet();
    if (returned.length != rows.length || !returned.every(ids.contains)) {
      throw const FormatException('Invalid or duplicate live review identity');
    }
    return MismatchReviewChanges(
      rows,
      '${result['source_version']}',
      '${result['snapshot']}',
    );
  }

  @override
  void watch(
    void Function(int? id) changed,
    void Function(bool live) connection,
  ) {
    _channel = client
        .channel('inventory-mismatch-review-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stk_mismatch',
          callback: (p) => changed(
            ((p.newRecord['id'] ?? p.oldRecord['id']) as num?)?.toInt(),
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inventory_mismatch_reviews',
          callback: (p) => changed(
            ((p.newRecord['mismatch_id'] ?? p.oldRecord['mismatch_id']) as num?)
                ?.toInt(),
          ),
        )
        .subscribe(
          (status, error) =>
              connection(status == RealtimeSubscribeStatus.subscribed),
        );
  }

  @override
  Future<void> close() async {
    if (_channel != null) await client.removeChannel(_channel!);
  }
}

/// Owns one screen subscription. A disconnect never turns an unknown into safe.
class MismatchReviewController extends ChangeNotifier {
  MismatchReviewController(this.repository);
  final MismatchReviewRepository repository;
  List<MismatchReview> rows = [];
  List<Map<String, dynamic>> coverage = [];
  bool loading = true,
      refreshing = false,
      live = false,
      refreshingEvidence = false;
  String? error;
  DateTime? syncedAt;
  int? lastChangedId;
  DateTime? lastChangedAt;
  Timer? _debounce, _poll;
  bool _disposed = false, _queued = false, _started = false;
  bool _patching = false;
  final _changedIds = <int>{};
  String _fullToken = '', _sourceVersion = '';
  int revision = 0;
  final _details =
      <int, ({String stamp, DateTime at, Map<String, dynamic> data})>{};
  final _detailRequests =
      <int, ({String stamp, Future<Map<String, dynamic>?> future})>{};
  final _detailEpochs = <int, int>{};
  String _detailStamp(MismatchReview row) =>
      '$_sourceVersion|${_detailEpochs[row.id] ?? 0}|${row.raw}';
  String detailKey(MismatchReview row) => _detailStamp(row);

  Map<String, dynamic>? cachedDetail(MismatchReview row) {
    final entry = _details.remove(row.id);
    if (entry == null ||
        entry.stamp != _detailStamp(row) ||
        DateTime.now().difference(entry.at) > const Duration(seconds: 45)) {
      return null;
    }
    _details[row.id] = entry;
    return entry.data;
  }

  /// Bounded, screen-local cache. Changes invalidate even an in-flight request.
  Future<Map<String, dynamic>?> detail(MismatchReview row) {
    final cached = cachedDetail(row);
    if (cached != null) return Future.value(cached);
    final stamp = _detailStamp(row);
    final pending = _detailRequests[row.id];
    if (pending?.stamp == stamp) return pending!.future;
    final future = repository
        .detail(row.id)
        .then((data) {
          if (!_disposed && data != null && stamp == _detailStamp(row)) {
            _details.remove(row.id);
            _details[row.id] = (stamp: stamp, at: DateTime.now(), data: data);
            while (_details.length > 12) {
              _details.remove(_details.keys.first);
            }
          }
          return data;
        })
        .whenComplete(() {
          if (_detailRequests[row.id]?.stamp == stamp) {
            _detailRequests.remove(row.id);
          }
        });
    _detailRequests[row.id] = (stamp: stamp, future: future);
    return future;
  }

  void start() {
    if (_started) return;
    _started = true;
    repository.watch(
      (id) {
        if (_disposed) return;
        if (id == null) {
          _details.clear();
          for (final key in _detailRequests.keys) {
            _detailEpochs[key] = (_detailEpochs[key] ?? 0) + 1;
          }
        } else {
          _details.remove(id);
          _detailEpochs[id] = (_detailEpochs[id] ?? 0) + 1;
        }
        if (id != null) _changedIds.add(id);
        lastChangedId = id;
        lastChangedAt = DateTime.now();
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 500), _applyChanges);
      },
      (connected) {
        if (_disposed) return;
        final reconnected = connected && !live;
        live = connected;
        notifyListeners();
        if (reconnected && !loading) unawaited(refresh());
      },
    );
    _poll = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _checkSnapshot(),
    );
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (refreshing || _patching) {
      _queued = true;
      return;
    }
    refreshing = true;
    notifyListeners();
    try {
      var snapshot = await repository.load();
      if (_disposed) return;
      rows = snapshot.rows;
      coverage = snapshot.coverage;
      _fullToken = snapshot.token;
      _sourceVersion = snapshot.sourceVersion;
      error = null;
      loading = false;
      syncedAt = DateTime.now();
      revision++;
      notifyListeners();
      final stale =
          rows.where((r) => r.stale || r.status == 'analysis_error').toList()
            ..sort(
              (a, b) => (b.eventAt ?? DateTime(1900)).compareTo(
                a.eventAt ?? DateTime(1900),
              ),
            );
      if (stale.isNotEmpty) {
        refreshingEvidence = true;
        notifyListeners();
        // Explicit write chunks, not bulk read pages. Keep expensive work bounded.
        for (var first = 0; first < stale.length && !_disposed; first += 100) {
          await repository.refreshReviews(
            stale.skip(first).take(100).map((r) => r.id).toList(),
          );
        }
        if (_disposed) return;
        snapshot = await repository.load();
        if (_disposed) return;
        rows = snapshot.rows;
        coverage = snapshot.coverage;
        _fullToken = snapshot.token;
        _sourceVersion = snapshot.sourceVersion;
        revision++;
        syncedAt = DateTime.now();
      }
    } catch (e) {
      if (!_disposed) {
        error = e is PostgrestException && e.code == '42501'
            ? 'This workspace requires an active Inventory account.'
            : 'The report could not sync. Previous data is retained. Retry to obtain current evidence.';
      }
    } finally {
      if (!_disposed) {
        loading = false;
        refreshing = false;
        refreshingEvidence = false;
        notifyListeners();
        if (_queued) {
          _queued = false;
          unawaited(refresh());
        } else if (_changedIds.isNotEmpty && !_patching) {
          unawaited(_applyChanges());
        }
      }
    }
  }

  Future<void> _checkSnapshot() async {
    if (_disposed || refreshing || _patching) return;
    try {
      final metadata = await repository.changes([]);
      if (_disposed) return;
      if (metadata == null ||
          metadata.token != _fullToken ||
          metadata.sourceVersion != _sourceVersion) {
        await refresh();
      } else {
        syncedAt = DateTime.now();
        error = null;
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed) unawaited(refresh());
    }
  }

  Future<void> _applyChanges() async {
    if (_disposed || refreshing || _patching) return;
    if (_changedIds.isEmpty) {
      await _checkSnapshot();
      return;
    }
    _patching = true;
    final ids = _changedIds.take(StockManagementLoadConfig.batchSize).toList();
    _changedIds.removeAll(ids);
    try {
      var changes = await repository.changes(ids);
      if (_disposed) return;
      if (changes == null || changes.sourceVersion != _sourceVersion) {
        await refresh();
        return;
      }
      if (changes.rows.any((r) => r.stale || r.status == 'analysis_error')) {
        await repository.refreshReviews(
          changes.rows
              .where((r) => r.stale || r.status == 'analysis_error')
              .map((r) => r.id)
              .toList(),
        );
        changes = await repository.changes(ids);
        if (_disposed) return;
        if (changes == null || changes.sourceVersion != _sourceVersion) {
          await refresh();
          return;
        }
      }
      final byId = {for (final row in rows) row.id: row};
      // IDs missing from this scoped response were deleted. Keep the last full
      // token, so periodic reconciliation can still detect missed events.
      for (final id in ids) {
        byId.remove(id);
      }
      for (final row in changes.rows) {
        byId[row.id] = row;
      }
      rows = byId.values.toList();
      error = null;
      syncedAt = DateTime.now();
      revision++;
      notifyListeners();
    } catch (_) {
      if (!_disposed) {
        error =
            'A live update could not sync. Retry to reconcile the current report.';
        notifyListeners();
      }
    } finally {
      _patching = false;
      if (!_disposed && _queued) {
        _queued = false;
        unawaited(refresh());
      } else if (!_disposed && _changedIds.isNotEmpty) {
        unawaited(_applyChanges());
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    _poll?.cancel();
    _details.clear();
    _detailRequests.clear();
    unawaited(repository.close());
    super.dispose();
  }
}
