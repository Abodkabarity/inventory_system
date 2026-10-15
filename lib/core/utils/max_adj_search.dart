import 'store_branch_identity_registry.dart';

/// PostgREST OR filters, including authoritative displayed branch names.
String maxAdjSearchFilter(String query) {
  String quoted(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  final search = query.trim();
  final filters = [
    for (final column in [
      'item_code',
      'item_name',
      'branch_name',
      'adjustment_type',
      'reason',
    ])
      '$column.ilike.${quoted('%$search%')}',
  ];
  final normalized = search.toUpperCase();
  for (final rawName in StoreBranchIdentityRegistry.groups.value.keys) {
    final display = StoreBranchIdentityRegistry.displayName(rawName);
    if (!rawName.contains(normalized) &&
        display.toUpperCase().contains(normalized)) {
      final literal = rawName.replaceAll('%', r'\%').replaceAll('_', r'\_');
      filters.add('branch_name.ilike.${quoted(literal)}');
    }
  }
  return filters.join(',');
}
