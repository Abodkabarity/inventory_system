import 'dart:io';

import 'package:daily_order/data/datasources/remote/zone_stock_check_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'zone 6 + 7 reads match authoritative totals and pending IDs',
    () async {
      final config = <String, String>{};
      for (final line in File('.env').readAsLinesSync()) {
        final equals = line.indexOf('=');
        if (equals < 1) continue;
        config[line.substring(0, equals).trim()] = line
            .substring(equals + 1)
            .trim()
            .replaceAll(RegExp(r'''^['"]|['"]$'''), '');
      }
      final client = SupabaseClient(
        config['SUPABASE_URL']!,
        config['SUPABASE_ANON_KEY']!,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final branches = await client
          .from('branches')
          .select('branch_name')
          .eq('is_active', true)
          .inFilter('zone', ['Zone6', 'Zone7']);
      final names = branches
          .map((row) => row['branch_name'] as String)
          .toList();
      final source = ZoneStockCheckRemoteDs(client);
      final details = await source.load(names);
      final pending = await source.load(names, pendingOnly: true);
      final expected = await client
          .from('stock_check_tasks')
          .select('id')
          .inFilter('branch_name', names)
          .limit(1)
          .count(CountOption.exact);
      final expectedPending = await client
          .from('stock_check_tasks')
          .select('id')
          .inFilter('branch_name', names)
          .eq('status', 'pending')
          .limit(1)
          .count(CountOption.exact);
      expect(details.length, expected.count);
      expect(details.map((row) => row.id).toSet().length, expected.count);
      expect(pending.length, expectedPending.count);
      expect(
        details.where((row) => row.isPending).map((row) => row.id).toSet(),
        pending.map((row) => row.id).toSet(),
      );
      // Report counts only; credentials and individual inventory values stay local.
      // ignore: avoid_print
      print(
        'Verified ${names.length} branches, ${details.length} tasks, ${pending.length} pending; Nadd Al Hamar: ${pending.where((row) => row.branchName == 'Nadd Al Hamar - DXB').length} pending.',
      );
    },
    skip: !const bool.fromEnvironment('RUN_STOCK_CHECK_LIVE_TEST'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
