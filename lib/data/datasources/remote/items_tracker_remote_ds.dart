import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/items_tracker_record.dart';
import '../../../domain/repositories/items_tracker_repository.dart';

class ItemsTrackerRemoteDs implements ItemsTrackerRepository {
  final SupabaseClient client;

  static const int _batchSize = 1000;

  ItemsTrackerRemoteDs(this.client);

  @override
  Future<List<ItemsTrackerRecord>> fetchRecords() async {
    final records = <ItemsTrackerRecord>[];
    var from = 0;
    while (true) {
      final response = await client
          .from('item_tracker_grid')
          .select()
          .order('assignment_priority')
          .order('updated_at', ascending: false)
          .order('id', ascending: false)
          .range(from, from + _batchSize - 1);
      final page = (response as List)
          .map(
            (row) => ItemsTrackerRecord.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);
      records.addAll(page);
      if (page.length < _batchSize) break;
      from += _batchSize;
    }
    return records;
  }

  @override
  Future<List<ItemsTrackerProduct>> searchProducts(String query) async {
    final cleaned = query.trim();
    if (cleaned.length < 2) return const [];
    final response = await client.rpc(
      'item_tracker_search_catalog',
      params: {'p_query': cleaned, 'p_limit': 12},
    );
    return (response as List)
        .map(
          (row) => ItemsTrackerProduct.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<String>> fetchItemStatuses() async {
    final response = await client.rpc('item_tracker_status_options');
    final statuses =
        (response as List)
            .map((row) {
              if (row is Map) {
                return (row['item_status'] ?? row['status'] ?? '').toString();
              }
              return row.toString();
            })
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort(
            (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
          );
    return statuses;
  }

  @override
  Future<void> createRecord(CreateItemsTrackerRecord input) async {
    await client.rpc(
      'item_tracker_create',
      params: {
        'p_escalated_date': _date(input.escalatedDate),
        'p_item_code': input.itemCode.trim(),
        'p_unit_cost': input.unitCost,
        'p_inventory_note': _nullableText(input.inventoryNote),
        'p_required_qty': input.requiredQty,
        'p_status_updated_to': input.statusUpdatedTo.trim(),
        'p_follow_up_role': input.followUpRole.trim().toLowerCase(),
      },
    );
  }

  @override
  Future<void> updateInventoryFields(UpdateItemsTrackerRecord input) async {
    await client.rpc(
      'item_tracker_update_inventory_fields',
      params: {
        'p_item_id': input.itemId,
        'p_escalated_date': _date(input.escalatedDate),
        'p_unit_cost': input.unitCost,
        'p_inventory_note': _nullableText(input.inventoryNote),
        'p_required_qty': input.requiredQty,
        'p_status_updated_to': input.statusUpdatedTo.trim(),
        'p_follow_up_role': input.followUpRole.trim().toLowerCase(),
        'p_expected_version': input.expectedVersion,
      },
    );
  }

  @override
  Future<void> addAction(AddItemsTrackerAction input) async {
    await client.rpc(
      'item_tracker_add_action',
      params: {
        'p_item_id': input.itemId,
        'p_action_date': _date(input.actionDate),
        'p_body': input.body.trim(),
        'p_case_status': input.caseStatus.trim().toLowerCase(),
        'p_expected_version': input.expectedVersion,
      },
    );
  }

  @override
  Future<void> changeFollowUp(ChangeItemsTrackerFollowUp input) async {
    await client.rpc(
      'item_tracker_change_follow_up',
      params: {
        'p_item_id': input.itemId,
        'p_target_role': input.targetRole.trim().toLowerCase(),
        'p_note': _nullableText(input.note),
        'p_action_date': _date(input.actionDate),
        'p_expected_version': input.expectedVersion,
      },
    );
  }

  @override
  Future<void> addComment({
    required String itemId,
    required String body,
  }) async {
    await client.rpc(
      'item_tracker_add_comment',
      params: {'p_item_id': itemId, 'p_body': body.trim()},
    );
  }

  @override
  Future<List<ItemsTrackerTimelineEntry>> fetchTimeline(String itemId) async {
    final response = await client.rpc(
      'item_tracker_fetch_timeline',
      params: {'p_item_id': itemId},
    );
    return (response as List)
        .map(
          (row) => ItemsTrackerTimelineEntry.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String? _nullableText(String value) {
    final cleaned = value.trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
