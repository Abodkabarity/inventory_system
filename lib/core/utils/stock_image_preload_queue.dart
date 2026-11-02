/// Bounded image warming. Closing the owning dialog cancels queued downloads.
/// Active downloads finish normally and remain available in the image cache.
class StockImagePreloadQueue {
  final Future<void> Function(String) load;
  final int concurrency;
  final _queued = <String>[];
  final _seen = <String>{};
  int _active = 0;
  bool _disposed = false;
  StockImagePreloadQueue({required this.load, this.concurrency = 2})
    : assert(concurrency > 0);

  void add(Iterable<String> urls) {
    if (_disposed) return;
    for (final url in urls) {
      if (_seen.add(url)) _queued.add(url);
    }
    while (_active < concurrency && _queued.isNotEmpty) {
      _active++;
      _run();
    }
  }

  Future<void> _run() async {
    try {
      while (!_disposed && _queued.isNotEmpty) {
        final url = _queued.removeAt(0);
        try {
          await load(url);
        } catch (_) {
          /* Optional preloading. */
        }
      }
    } finally {
      _active--;
    }
  }

  void dispose() {
    _disposed = true;
    _queued.clear();
  }
}
