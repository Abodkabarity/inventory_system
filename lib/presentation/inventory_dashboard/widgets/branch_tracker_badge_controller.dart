import 'dart:async';

import 'package:flutter/foundation.dart';

typedef BranchTrackerBadgeLoader =
    Future<int> Function(DateTime since, bool inclusive);

/// Groups source-table events and allows only one badge request at a time.
class BranchTrackerBadgeController extends ChangeNotifier {
  BranchTrackerBadgeController({
    required this.loadCount,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final BranchTrackerBadgeLoader loadCount;
  final DateTime Function() _now;
  static const _refreshDelay = Duration(seconds: 3);

  int count = 0;
  bool loading = true;
  DateTime? _lastSeenAt;
  Timer? _timer;
  bool _initialized = false;
  bool _disposed = false;
  bool _running = false;
  bool _pending = false;
  int _generation = 0;

  Future<void> initialize(DateTime? lastSeenAt) async {
    if (_disposed) return;
    _lastSeenAt = lastSeenAt;
    _initialized = true;
    _pending = true;
    await _refresh();
  }

  void scheduleRefresh() {
    if (_disposed || !_initialized) return;
    _pending = true;
    _armTimer();
  }

  void markSeen(DateTime seenAt) {
    if (_disposed) return;
    _generation++;
    _lastSeenAt = seenAt;
    count = 0;
    loading = false;
    notifyListeners();
    // An older request must not restore already-seen changes. Read again using
    // the new cutoff to include events arriving while that request was running.
    scheduleRefresh();
  }

  void _armTimer() {
    if (_timer != null || _disposed) return;
    // Keep the first timer during a burst so continuous activity cannot postpone
    // the badge indefinitely.
    _timer = Timer(_refreshDelay, () {
      _timer = null;
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_disposed || _running || !_pending) return;
    _pending = false;
    _running = true;
    final generation = _generation;
    final lastSeenAt = _lastSeenAt;
    final now = _now();
    final since =
        lastSeenAt ??
        DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29));
    try {
      final result = await loadCount(since.toUtc(), lastSeenAt == null);
      if (!_disposed && generation == _generation) {
        count = result.clamp(0, 1000);
        loading = false;
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        // A temporary API failure should not erase a previously loaded badge.
        loading = false;
        notifyListeners();
      }
    } finally {
      _running = false;
      if (_pending && !_disposed) _armTimer();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
