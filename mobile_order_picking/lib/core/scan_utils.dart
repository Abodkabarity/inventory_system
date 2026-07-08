String normalizeScanValue(String value) {
  var out = value.trim();
  if (out.endsWith('.0')) out = out.substring(0, out.length - 2);
  return out.replaceAll(RegExp(r'\s+'), '');
}

bool scanMatches({
  required String scanned,
  required String itemCode,
  required String barcode,
  List<String> validBarcodes = const [],
}) {
  final normalized = normalizeScanValue(scanned).toLowerCase();
  if (normalized.isEmpty) return false;
  final candidates = {
    normalizeScanValue(itemCode).toLowerCase(),
    normalizeScanValue(barcode).toLowerCase(),
    ...validBarcodes.map((e) => normalizeScanValue(e).toLowerCase()),
  }..removeWhere((e) => e.isEmpty);
  return candidates.contains(normalized);
}
