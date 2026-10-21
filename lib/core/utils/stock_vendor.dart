/// A consistent, uppercase vendor label, limited to ten Unicode characters.
String formatStockVendor(Object? vendor) => String.fromCharCodes(
  (vendor?.toString() ?? '').trim().toUpperCase().runes.take(10),
);
