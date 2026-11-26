/// Application-wide default for bulk reads and file-import row batches.
/// Explicit small pages, metadata, key lists and specialized writes keep their
/// own limits; server RPCs must accept this size before adopting it.
abstract final class DataBatchConfig {
  static const batchSize = 4000;
}
