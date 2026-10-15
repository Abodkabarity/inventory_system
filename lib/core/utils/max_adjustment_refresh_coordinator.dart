import 'dart:async';

/// Coalesces row notifications without restarting an in-flight full refresh.
class MaxAdjustmentRefreshCoordinator {
  MaxAdjustmentRefreshCoordinator({
    required this.onRefresh,
    this.quietPeriod = const Duration(milliseconds: 600),
  });

  final void Function() onRefresh;
  final Duration quietPeriod;
  Timer? _timer;
  bool _paused = false;
  bool _loading = false;
  bool _dirty = false;
  bool _disposed = false;

  void changed() {
    if (_disposed) return;
    _dirty = true;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || _paused || _loading || !_dirty) return;
    _timer = Timer(quietPeriod, () {
      _dirty = false;
      onRefresh();
    });
  }

  void beginLoad() {
    _timer?.cancel();
    _loading = true;
    _dirty = false;
  }

  void endLoad() {
    _loading = false;
    _schedule();
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
  }

  void resume({bool alreadyRefreshed = false}) {
    _paused = false;
    _loading = false;
    if (alreadyRefreshed) _dirty = false;
    _schedule();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
