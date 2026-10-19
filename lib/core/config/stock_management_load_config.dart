/// Shared bulk-loading policy for Overview, MRN Overview and Near Expiry.
abstract final class StockManagementLoadConfig {
  static const batchSize = 5000;
}
