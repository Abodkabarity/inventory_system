import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Store-only display metadata for branches.
///
/// Branch names remain untouched for queries, matching, exports, and writes.
/// This registry only decorates names whose authoritative `branch_group` is 71.
class StoreBranchIdentityRegistry {
  StoreBranchIdentityRegistry._();

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
      groups.value = Map<String, String>.unmodifiable(next);
    } catch (_) {
      // Display metadata must never block Store workflows or printing.
    }
  }

  static bool isSeventyOne(String? branchName, [Map<String, String>? source]) {
    final group = (source ?? groups.value)[_key(branchName)];
    return group?.trim() == '71';
  }
}
