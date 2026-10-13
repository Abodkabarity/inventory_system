import 'store_branch_identity_registry.dart';

/// Rewrites one CSV field while leaving every other field byte-for-byte intact.
/// Used by the large streamed daily-order export to avoid parsing whole batches.
String decorateBranchCsvField(String line, int columnIndex) {
  if (line.isEmpty || columnIndex < 0) return line;
  var field = 0;
  var start = 0;
  var quoted = false;
  for (var i = 0; i <= line.length; i++) {
    if (i < line.length && line.codeUnitAt(i) == 34) {
      if (quoted && i + 1 < line.length && line.codeUnitAt(i + 1) == 34) {
        i++;
      } else {
        quoted = !quoted;
      }
    }
    if (i != line.length && (line.codeUnitAt(i) != 44 || quoted)) continue;
    if (field == columnIndex) {
      final raw = line.substring(start, i);
      final name = raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')
          ? raw.substring(1, raw.length - 1).replaceAll('""', '"')
          : raw;
      final display = StoreBranchIdentityRegistry.displayName(name);
      if (display == name) return line;
      final escaped = '"${display.replaceAll('"', '""')}"';
      return '${line.substring(0, start)}$escaped${line.substring(i)}';
    }
    field++;
    start = i + 1;
  }
  return line;
}
