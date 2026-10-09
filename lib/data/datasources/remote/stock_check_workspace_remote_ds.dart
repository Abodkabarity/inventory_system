import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/stock_check_campaign.dart';
import '../../../domain/entities/stock_check_task.dart';

class StockCheckWorkspaceRemoteDs {
  final SupabaseClient client;
  final Map<String, Future<List<StockCheckTask>>> _details = {};
  StockCheckWorkspaceRemoteDs(this.client);

  void invalidate() => _details.clear();

  Future<({String id, String name})> currentSender() async {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('Sign in before sending a Stock Check.');
    final profile = await client
        .from('app_users')
        .select('role,user_name,is_active')
        .eq('user_id', id)
        .maybeSingle();
    // Branch accounts submit counts without a personal user_name. They must
    // never become the sender of the campaign they are responding to.
    if ((profile?['role'] ?? '').toString().trim().toLowerCase() == 'branch') {
      return (id: id, name: '');
    }
    final name = (profile?['user_name'] ?? '').toString().trim();
    if (profile == null || profile['is_active'] != true || name.isEmpty) {
      throw StateError(
        'Your app_users profile needs an active account and user_name before sending.',
      );
    }
    return (id: id, name: name);
  }

  Future<List<StockCheckCampaign>> campaigns(List<String> sources) async {
    final result = <StockCheckCampaign>[];
    // Explicit pagination also handles installations with a 1,000-row API cap.
    for (var offset = 0; ; offset += 1000) {
      final page = await client
          .from('stock_check_campaigns')
          .select()
          .inFilter('source', sources)
          .order('sent_at', ascending: false)
          .order('batch_id')
          .range(offset, offset + 999);
      result.addAll(page.map(StockCheckCampaign.new));
      if (page.length < 1000) break;
    }
    return result;
  }

  Future<List<StockCheckTask>> details(String batchId, int total) {
    return _details.putIfAbsent(batchId, () async {
      try {
        final result = <StockCheckTask>[];
        // Bounded parallel requests: large campaigns need not wait for every
        // individual page in sequence, and rows are never silently truncated.
        for (var offset = 0; offset < total; offset += 4000) {
          final pages = await Future.wait([
            for (
              var start = offset;
              start < offset + 4000 && start < total;
              start += 1000
            )
              client
                  .from('stock_check_tasks')
                  .select()
                  .eq('batch_id', batchId)
                  .order('id')
                  .range(start, start + 999),
          ]);
          for (final page in pages) {
            result.addAll(page.map(StockCheckTask.fromMap));
          }
        }
        if (result.length != total) {
          throw StateError(
            'Campaign changed while loading. Refresh and try again.',
          );
        }
        return result;
      } catch (_) {
        _details.remove(batchId);
        rethrow;
      }
    });
  }
}
