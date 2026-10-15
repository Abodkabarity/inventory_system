/// Load the whole result set for one virtualized grid. Transport batches keep
/// requests within API limits; they are never exposed as UI pages.
Future<List<Map<String, dynamic>>?> loadMaxAdjustmentRows({
  required Future<Map<String, dynamic>> Function(int from, int to) fetchRange,
  bool Function()? isCancelled,
  void Function(int loaded, int total)? onProgress,
}) async {
  const batchSize = 500;
  final rows = <Map<String, dynamic>>[];
  while (true) {
    if (isCancelled?.call() ?? false) return null;
    final result = await fetchRange(rows.length, rows.length + batchSize - 1);
    if (isCancelled?.call() ?? false) return null;
    final batch = List<Map<String, dynamic>>.from(result['rows'] ?? []);
    final total = (result['total'] as num).toInt();
    if (batch.isEmpty) {
      if (rows.length < total) {
        throw StateError('Max adjustments returned an incomplete result set.');
      }
      return rows;
    }
    rows.addAll(batch);
    onProgress?.call(rows.length, total);
    if (rows.length >= total) return rows;
  }
}
