import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/items_tracker_record.dart';
import '../../../domain/repositories/items_tracker_repository.dart';

class ItemsTrackerRemoteDs implements ItemsTrackerRepository {
  final SupabaseClient client;

  static const int _batchSize = 1000;
  static const String attachmentsBucket = 'items-tracker-files';

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
  Future<void> updateStatusUpdatedTo(UpdateItemsTrackerStatus input) async {
    await client.rpc(
      'item_tracker_update_status_updated_to',
      params: {
        'p_item_id': input.itemId,
        'p_status_updated_to': input.statusUpdatedTo.trim(),
        'p_expected_version': input.expectedVersion,
      },
    );
  }

  @override
  Future<void> updateTrackerStatus(UpdateItemsTrackerCaseStatus input) async {
    await client.rpc(
      'item_tracker_update_tracker_status',
      params: {
        'p_item_id': input.itemId,
        'p_tracker_status': input.trackerStatus.trim().toLowerCase(),
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

  @override
  Future<void> uploadAttachment({
    required String itemId,
    required ItemsTrackerUploadFile file,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('You must be signed in to upload a file.');
    }

    final safeName = _safeFileName(file.name);
    final storagePath = '$itemId/$userId/${const Uuid().v4()}_$safeName';
    await client.storage
        .from(attachmentsBucket)
        .uploadBinary(
          storagePath,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
        );

    try {
      await client.rpc(
        'item_tracker_register_attachment',
        params: {
          'p_item_id': itemId,
          'p_storage_path': storagePath,
          'p_file_name': file.name.trim(),
          'p_mime_type': file.mimeType,
          'p_file_size': file.size,
        },
      );
    } catch (_) {
      try {
        await client.storage.from(attachmentsBucket).remove([storagePath]);
      } catch (_) {
        // Registration is authoritative. A failed best-effort cleanup must not
        // hide the original database error from the user.
      }
      rethrow;
    }
  }

  @override
  Future<String> createAttachmentDownloadUrl(String storagePath) {
    return client.storage
        .from(attachmentsBucket)
        .createSignedUrl(storagePath, 120);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String? _nullableText(String value) {
    final cleaned = value.trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static String _safeFileName(String value) {
    final normalized = value.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );
    if (normalized.isEmpty) return 'attachment';
    return normalized.length <= 120
        ? normalized
        : normalized.substring(normalized.length - 120);
  }
}
