import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/all_branches_trial_config.dart';
import '../../../domain/entities/stock_management.dart'
    show stockMap, stockNumber;
import 'online_overview_remote_ds.dart' show loadOnlineSource, OnlineSourcePage;

class AllBranchesTrialSnapshot {
  final Map<String, dynamic> meta;
  final List<Map<String, dynamic>> rows;
  const AllBranchesTrialSnapshot(this.meta, this.rows);
  String get generation => '${meta['generation']}';
  Map<String, String> get groups => {
    for (final raw in (meta['branches'] as List))
      '${raw['name']}'.trim().toUpperCase(): '${raw['group'] ?? ''}',
  };
}

abstract class AllBranchesTrialDataSource {
  Future<AllBranchesTrialSnapshot> load();
  Future<Map<String, dynamic>> details(String generation, String code);
}

class AllBranchesTrialRemoteDs implements AllBranchesTrialDataSource {
  AllBranchesTrialRemoteDs(this.client);
  final SupabaseClient client;
  void _check(String? id) {
    if (!AllBranchesTrialConfig.canAccess(id) ||
        client.auth.currentUser?.id != id) {
      throw StateError('This trial is not available for this account.');
    }
  }

  @override
  Future<AllBranchesTrialSnapshot> load() async {
    final id = client.auth.currentUser?.id;
    _check(id);
    final meta = stockMap(await client.rpc('get_local_all_branches_trial'));
    _check(id);
    final generation = '${meta['generation'] ?? ''}';
    final total = stockNumber(meta['items']).toInt();
    if (generation.isEmpty ||
        meta['scope'] != 'all_branches_trial' ||
        total < 1) {
      throw StateError('Prepare the complete trial first.');
    }
    final rows = await loadOnlineSource(
      expectedTotal: total,
      fetch: (offset, limit) async {
        final page = stockMap(
          await client.rpc(
            'get_local_all_branches_trial',
            params: {
              'p_action': 'batch',
              'p_generation': generation,
              'p_offset': offset,
              'p_limit': limit,
            },
          ),
        );
        _check(id);
        if (page['generation'] != generation) {
          throw StateError('Trial changed. Reload.');
        }
        return OnlineSourcePage([
          for (final row in page['rows'] as List) stockMap(row),
        ], stockNumber(page['total']).toInt());
      },
      identity: (row) => '${row['code'] ?? ''}',
    );
    for (final row in rows) {
      if (!{
            'A',
            'B',
            'C',
            'N',
            'M',
            'T',
            'S',
            'REVIEW',
          }.contains(row['rank']) ||
          (stockNumber(row['online_sales']) +
                      stockNumber(row['other_sales']) -
                      stockNumber(row['total_sales']))
                  .abs() >
              .00001) {
        throw StateError('Trial facts are inconsistent. Reload.');
      }
    }
    return AllBranchesTrialSnapshot(meta, List.unmodifiable(rows));
  }

  @override
  Future<Map<String, dynamic>> details(String generation, String code) async {
    final id = client.auth.currentUser?.id;
    _check(id);
    final data = stockMap(
      await client.rpc(
        'get_local_all_branches_trial',
        params: {
          'p_action': 'details',
          'p_generation': generation,
          'p_item_code': code,
        },
      ),
    );
    _check(id);
    if (data['generation'] != generation || data['code'] != code) {
      throw StateError('Trial changed. Reload.');
    }
    return data;
  }
}
