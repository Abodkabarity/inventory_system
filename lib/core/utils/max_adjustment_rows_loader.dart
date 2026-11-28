import '../config/data_batch_config.dart';

/// Load the whole virtualized grid, with at most two transport requests in
/// flight after the first batch establishes the total and the API's row cap.
/// No partial table is published, so sorting/filtering still cover every row.
Future<List<Map<String, dynamic>>?> loadMaxAdjustmentRows({
  required Future<Map<String, dynamic>> Function(int from, int to) fetchRange,
  bool Function()? isCancelled,
  void Function(int loaded, int total)? onProgress,
}) async {
  final rows = <Map<String, dynamic>>[];
  final ids = <Object>{};
  int? expectedTotal;
  var effectiveBatchSize = DataBatchConfig.batchSize;
  bool cancelled() => isCancelled?.call() ?? false;

  void append(Map<String, dynamic> result) {
    final batch = List<Map<String, dynamic>>.from(result['rows'] ?? []);
    final total = (result['total'] as num).toInt();
    expectedTotal ??= total;
    if (total != expectedTotal) {
      throw StateError('Max adjustments changed during loading. Please retry.');
    }
    if (batch.isEmpty && rows.length < total) {
      throw StateError('Max adjustments returned an incomplete result set.');
    }
    for (final row in batch) {
      final id = row['id'];
      if (id != null && !ids.add(id)) {
        throw StateError(
          'Max adjustments changed during loading. Please retry.',
        );
      }
    }
    rows.addAll(batch);
    if (rows.length > total) {
      throw StateError('Max adjustments returned an inconsistent result set.');
    }
    onProgress?.call(rows.length, total);
  }

  if (cancelled()) return null;
  final first = await fetchRange(0, DataBatchConfig.batchSize - 1);
  if (cancelled()) return null;
  append(first);
  if (rows.length >= expectedTotal!) return rows;
  effectiveBatchSize = rows.length.clamp(1, DataBatchConfig.batchSize);

  while (rows.length < expectedTotal!) {
    if (cancelled()) return null;
    final start = rows.length;
    final requests = <Future<Map<String, dynamic>>>[];
    for (
      var offset = start;
      offset < expectedTotal! && requests.length < 2;
      offset += effectiveBatchSize
    ) {
      requests.add(fetchRange(offset, offset + effectiveBatchSize - 1));
    }
    // Preserve server ordering even when the second response arrives first.
    final batches = await Future.wait(requests);
    if (cancelled()) return null;
    for (final batch in batches) {
      final count = (batch['rows'] as List?)?.length ?? 0;
      append(batch);
      if (rows.length < expectedTotal! && count < effectiveBatchSize) {
        throw StateError('Max adjustments returned an incomplete result set.');
      }
    }
  }
  return rows;
}
