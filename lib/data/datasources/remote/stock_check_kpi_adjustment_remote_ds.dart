import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/stock_management_load_config.dart';
import '../../../domain/entities/stock_check_campaign.dart';
import '../../../domain/entities/stock_check_kpi_adjustment.dart';

class StockCheckKpiAdjustmentRemoteDs {
  final SupabaseClient client;
  StockCheckKpiAdjustmentRemoteDs(this.client);

  Future<StockCheckKpiAdjustments> load(
    List<StockCheckCampaign> projects,
  ) async {
    final values = <String, StockCheckKpiAdjustment>{};
    String afterBranch = '', afterCode = '';
    String? snapshot;
    DateTime? from, through;
    int? total;
    do {
      final page = Map<String, dynamic>.from(
        await client.rpc(
              'stock_check_kpi_adjustments',
              params: {
                'p_project_ids': projects.map((p) => p.id).toList(),
                'p_after_branch': afterBranch,
                'p_after_code': afterCode,
                'p_limit': StockManagementLoadConfig.batchSize,
                'p_snapshot': snapshot,
                'p_through': through?.toIso8601String().split('T').first,
              },
            )
            as Map,
      );
      final pageSnapshot = page['snapshot'] as String;
      final pageFrom = DateTime.parse(page['from_date'] as String);
      final pageThrough = DateTime.parse(page['through_date'] as String);
      final pageTotal = (page['total'] as num).toInt();
      if (pageSnapshot.isEmpty ||
          pageTotal < 0 ||
          (snapshot != null &&
              (snapshot != pageSnapshot ||
                  total != pageTotal ||
                  from != pageFrom ||
                  through != pageThrough))) {
        throw StateError('Adjustment history changed while loading. Retry.');
      }
      snapshot = pageSnapshot;
      from = pageFrom;
      through = pageThrough;
      total = pageTotal;
      final rows = page['rows'] as List;
      if (rows.length > StockManagementLoadConfig.batchSize) {
        throw StateError('Invalid adjustment page size.');
      }
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final branch = row['branch'] as String;
        final code = row['item_code'] as String;
        final key = StockCheckKpiAdjustments.key(branch, code);
        final quantity = num.tryParse('${row['qty']}');
        final count = (row['movement_count'] as num).toInt();
        if (values.containsKey(key) ||
            quantity == null ||
            !quantity.isFinite ||
            count < 0 ||
            row['complete'] is! bool ||
            branch.trim().isEmpty ||
            code.trim().isEmpty) {
          throw StateError('Invalid or duplicate adjustment row. Retry.');
        }
        values[key] = StockCheckKpiAdjustment(
          quantity: quantity,
          movementCount: count,
          complete: row['complete'] as bool,
        );
      }
      if (values.length > total) throw StateError('Invalid adjustment total.');
      if (page['has_more'] == false) break;
      final nextBranch = page['next_branch'] as String;
      final nextCode = page['next_code'] as String;
      if (rows.isEmpty ||
          nextBranch.compareTo(afterBranch) < 0 ||
          (nextBranch == afterBranch && nextCode.compareTo(afterCode) <= 0)) {
        throw StateError('Adjustment page did not advance. Retry.');
      }
      afterBranch = nextBranch;
      afterCode = nextCode;
    } while (true);
    if (values.length != total) {
      throw StateError('Incomplete adjustment history. Retry.');
    }
    return StockCheckKpiAdjustments(
      fromDate: from,
      throughDate: through,
      snapshot: snapshot,
      values: values,
    );
  }
}
