/// Set to false to immediately disable optional Overview image lookups.
class StockProductImageConfig {
  static const enabled = bool.fromEnvironment(
    'STOCK_PRODUCT_IMAGES',
    defaultValue: true,
  );
}
