/// Shared bulk-loading policy for Overview, MRN, MRN CD and Near Expiry.
abstract final class StockManagementLoadConfig {
  static const batchSize = 4000;
}
