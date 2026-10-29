import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App-wide display metadata for branches.
///
/// Raw branch names remain untouched for queries, matching, and writes.
/// Labels and exported branch cells use [displayName].
/// This registry only decorates names whose authoritative `branch_group` is 71.
class StoreBranchIdentityRegistry {
  StoreBranchIdentityRegistry._();

  static const _branchExportColumns = <String>{
    'branch',
    'branch_name',
    'BRANCH',
    'Branch',
    'Branch Name',
    'Warehouse',
    'warehouse',
    'from_branch',
    'to_branch',
    'source_branch',
    'destination_branch',
    'From Branch',
    'To Branch',
    'Source Branch',
    'Destination Branch',
  };

  static final ValueNotifier<Map<String, String>> groups =
      ValueNotifier<Map<String, String>>(const {});

  static Future<void>? _loading;

  static String _key(String? branchName) =>
      (branchName ?? '').trim().toUpperCase();

  static Future<void> load(SupabaseClient client, {bool force = false}) async {
    if (!force && groups.value.isNotEmpty) return;
    if (!force && _loading != null) return _loading!;

    _loading = _fetch(client);
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  static Future<void> _fetch(SupabaseClient client) async {
    try {
      final response = await client
          .from('branches')
          .select('branch_name, branch_group');
      final next = <String, String>{};
      for (final raw in List<Map<String, dynamic>>.from(response)) {
        final name = (raw['branch_name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        next[_key(name)] = (raw['branch_group'] ?? '').toString().trim();
      }
      if (client.auth.currentSession != null) {
        groups.value = Map<String, String>.unmodifiable(next);
      }
    } catch (_) {
      // Display metadata must never block Store workflows or printing.
    }
  }

  static bool isSeventyOne(String? branchName, [Map<String, String>? source]) {
    final group = (source ?? groups.value)[_key(branchName)];
    return group?.trim() == '71';
  }

  /// Use only for labels and exported cells. Keep the original name for
  /// database filters, grouping, imports, and file paths.
  static String displayName(String? branchName, [Map<String, String>? source]) {
    final name = (branchName ?? '').trim();
    if (name.isEmpty || !isSeventyOne(name, source)) return name;
    if (name.startsWith('71 ')) return name;
    return '71 $name';
  }

  static Object? exportValue(String column, Object? value) {
    if (_branchExportColumns.contains(column)) {
      return displayName(value?.toString());
    }
    return value;
  }
}
