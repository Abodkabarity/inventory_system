import '../../domain/entities/additional_request_group.dart';
import '../../domain/entities/product_movement.dart';
import '../../domain/entities/store_order_item.dart';
import '../../domain/repositories/store_repository.dart';
import '../datasources/remote/store_remote_ds.dart';

class StoreRepositoryImpl implements StoreRepository {
  final StoreRemoteDs remote;

  StoreRepositoryImpl(this.remote);

  /// =========================================
  /// FIX BARCODE FORMAT (NO SCIENTIFIC FORMAT)
  /// =========================================
  String _formatBarcode(dynamic value) {
    if (value == null) return '';

    if (value is int) {
      return value.toString();
    }

    if (value is double) {
      return value.toStringAsFixed(0);
    }

    final s = value.toString();

    if (s.contains('E+') || s.contains('e+')) {
      final d = double.tryParse(s);
      if (d != null) {
        return d.toStringAsFixed(0);
      }
    }

    return s.replaceAll('.0', '');
  }

  /// ================================
  /// ALL BRANCHES
  /// ================================
  @override
  Future<List<String>> fetchActiveBranchNames() {
    return remote.fetchActiveBranchNames();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTodayBranches() async {
    return await remote.fetchTodayBranches();
  }

  @override
  Future<void> markBranchPrinted({
    required String runDate,
    required String branch,
  }) {
    return remote.markBranchPrinted(runDate: runDate, branch: branch);
  }

  /// ================================
  /// SUBMITTED BRANCHES
  /// ================================
  @override
  Future<List<Map<String, dynamic>>> fetchSubmittedBranches(
    String runDate,
  ) async {
    return await remote.fetchSubmittedBranches(runDate);
  }

  /// ================================
  /// BRANCH ITEMS
  /// ================================
  @override
  Future<List<StoreOrderItem>> fetchBranchItems({
    required String runDate,
    required String branch,
  }) async {
    final rows = await remote.fetchBranchItems(
      runDate: runDate,
      branch: branch,
    );

    return rows.map((e) {
      return StoreOrderItem(
        itemCode: (e['item_code'] ?? '').toString(),
        itemName: (e['item_name'] ?? '').toString(),
        barcode: _formatBarcode(e['barcode']),
        supplier: (e['supplier'] ?? '').toString(),
        classification: (e['store_item_classifications'] ?? '').toString(),
        category: (e['category'] ?? '').toString(),
        quantity: num.tryParse((e['final_qty'] ?? '0').toString()) ?? 0,
      );
    }).toList();
  }

  /// ================================
  /// ADDITIONAL REQUESTS (FIXED COUNT)
  /// ================================
  @override
  Future<List<AdditionalRequestGroup>> fetchAdditionalRequests() async {
    final rows = await remote.fetchAdditionalRequestGroups();

    final uniqueRows = <Map<String, dynamic>>[];
    final seenRows = <String>{};

    for (final row in rows) {
      final id = (row['id'] ?? '').toString();
      final fallbackKey = [
        row['request_group_id'],
        row['branch_name'],
        row['created_at'],
        row['item_code'],
        row['request_qty'],
        row['status'],
        row['store_status'],
      ].map((e) => (e ?? '').toString()).join('|');

      final key = id.trim().isNotEmpty ? 'id:$id' : 'fallback:$fallbackKey';
      if (seenRows.add(key)) {
        uniqueRows.add(row);
      }
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final row in uniqueRows) {
      final groupId = (row['request_group_id'] ?? '').toString();
      final sourceTable = (row['_source_table'] ?? 'additional_requests')
          .toString();

      final branch = (row['branch_name'] ?? '').toString();
      // An Inventory Additional Order is one request that may target many
      // branches. Keep it together in Store; branch requests keep their
      // existing per-branch grouping.
      final key = sourceTable == 'additional_order_inventory'
          ? '$sourceTable|$groupId'
          : '$sourceTable|$groupId|$branch';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(row);
    }

    final List<AdditionalRequestGroup> result = [];

    grouped.forEach((_, items) {
      final first = items.first;
      final groupId = (first['request_group_id'] ?? '').toString();
      final sourceTable = (first['_source_table'] ?? 'additional_requests')
          .toString();

      DateTime created;
      final createdRaw = first['created_at'];

      if (createdRaw == null) {
        created = DateTime.now().toLocal();
      } else {
        created = (DateTime.tryParse(createdRaw.toString()) ?? DateTime.now())
            .toLocal();
      }

      final validItems = items.where((e) {
        final inv = e['inventory_qty'];

        if (inv == null) return true;
        return inv > 0;
      }).toList();
      if (validItems.isEmpty) {
        return;
      }
      final hasPending = validItems.any((e) => e['status'] == 'sent_to_store');

      final allRejected = validItems.every((e) => e['status'] == 'rejected');

      String status;

      if (hasPending) {
        status = 'sent_to_store';
      } else if (allRejected) {
        status = 'rejected';
      } else {
        // done OR mixed(done + rejected)
        status = 'done';
      }
      final isUrgent = validItems.any((e) => e['contact_logistic'] == 'urgent');
      final isProcessing = validItems.any(
        (e) => e['store_status'] == 'processing',
      );
      final pendingItems = validItems.where((e) {
        final status = (e['status'] ?? '').toString();
        final storeStatus = (e['store_status'] ?? '').toString();
        return status == 'sent_to_store' && storeStatus != 'processing';
      }).toList();
      final classifications =
          validItems
              .map((e) => (e['store_item_classifications'] ?? '').toString())
              .map((e) => e.trim().isEmpty ? 'MEDICINE' : e.trim())
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final pendingClassifications =
          pendingItems
              .map((e) => (e['store_item_classifications'] ?? '').toString())
              .map((e) => e.trim().isEmpty ? 'MEDICINE' : e.trim())
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final itemCodes =
          validItems
              .map((e) => (e['item_code'] ?? '').toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final itemNames =
          validItems
              .map((e) => (e['item_name'] ?? '').toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      result.add(
        AdditionalRequestGroup(
          groupId: groupId,
          branchName: sourceTable == 'additional_order_inventory'
              ? ''
              : (first['branch_name'] ?? '').toString(),
          createdAt: created,
          itemsCount: validItems.length,
          status: status,
          itemNames: itemNames.join(', '),
          itemCodes: itemCodes.join(', '),
          classifications: classifications,
          pendingClassifications: pendingClassifications,
          storeStatus: isProcessing ? 'processing' : null,
          contactLogistic: isUrgent ? 'urgent' : '',
          sourceTable: (first['_source_table'] ?? 'additional_requests')
              .toString(),
        ),
      );
    });

    final deduped = <String, AdditionalRequestGroup>{};
    for (final group in result) {
      final key = [
        group.sourceTable,
        group.branchName,
        group.createdAt.toIso8601String(),
        group.status,
        group.storeStatus ?? '',
        group.itemCodes,
        group.itemNames,
        group.itemsCount,
      ].join('|');

      deduped.putIfAbsent(key, () => group);
    }

    final finalResult = deduped.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return finalResult;
  }

  /// ================================
  /// APPROVE REQUEST
  /// ================================
  @override
  Future<void> approveRequest({
    required String id,
    required num qty,
    String sourceTable = 'additional_requests',
  }) {
    return remote.approveRequest(id: id, qty: qty, sourceTable: sourceTable);
  }

  /// ================================
  /// ADDITIONAL HISTORY (FIXED COUNT)
  /// ================================
  @override
  Future<List<AdditionalRequestGroup>> fetchAdditionalHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await remote.fetchAdditionalHistory(from: from, to: to);

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final row in rows) {
      final sourceTable = (row['_source_table'] ?? 'additional_requests')
          .toString();
      final groupId = sourceTable == 'additional_order_inventory'
          ? '$sourceTable|${row['request_group_id']}'
          : '$sourceTable|${row['request_group_id']}|${row['branch_name']}';

      grouped.putIfAbsent(groupId, () => []);
      grouped[groupId]!.add(row);
    }

    final result = <AdditionalRequestGroup>[];

    grouped.forEach((groupId, items) {
      final first = items.first;
      final sourceTable = (first['_source_table'] ?? 'additional_requests')
          .toString();

      final itemNames = items
          .map((e) => (e['item_name'] ?? '').toString())
          .join(', ');

      final itemCodes = items
          .map((e) => (e['item_code'] ?? '').toString())
          .join(', ');

      final validItems = items.where((e) {
        final inv = e['inventory_qty'];

        if (inv == null) return true;
        return inv > 0;
      }).toList();
      if (validItems.isEmpty) {
        return;
      }
      final hasPending = validItems.any((e) => e['status'] == 'sent_to_store');

      final allRejected = validItems.every((e) => e['status'] == 'rejected');

      String status;

      if (hasPending) {
        status = 'sent_to_store';
      } else if (allRejected) {
        status = 'rejected';
      } else {
        // done OR mixed(done + rejected)
        status = 'done';
      }
      final isProcessing = validItems.any(
        (e) => e['store_status'] == 'processing',
      );
      result.add(
        AdditionalRequestGroup(
          groupId: first['request_group_id'].toString(),
          branchName: sourceTable == 'additional_order_inventory'
              ? ''
              : first['branch_name'],
          createdAt: DateTime.parse(first['created_at']).toLocal(),
          itemsCount: validItems.length,
          status: status,
          itemNames: itemNames,
          itemCodes: itemCodes,
          storeStatus: isProcessing ? 'processing' : null,
          contactLogistic: (first['contact_logistic'] ?? '').toString(),
          sourceTable: (first['_source_table'] ?? 'additional_requests')
              .toString(),
        ),
      );
    });

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAllSentToStore() {
    return remote.fetchAllSentToStore();
  }

  @override
  Future<List<String>> fetchSeventyOneBranchNames() {
    return remote.fetchSeventyOneBranchNames();
  }

  @override
  Future<void> markAsProcessing(List<Map<String, dynamic>> rows) {
    return remote.markAsProcessing(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchProcessingRequests() {
    return remote.fetchProcessingRequests();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchProductSuggestions({
    required String branch,
    required String query,
  }) {
    return remote.fetchProductSuggestions(branch: branch, query: query);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMovementProductSuggestions({
    required String query,
  }) {
    return remote.fetchMovementProductSuggestions(query: query);
  }

  @override
  Future<List<ProductMovement>> fetchProductMovement({
    required String query,
    required String? branch,
    required DateTime from,
    required DateTime to,
    required String movementType,
  }) async {
    final rows = await remote.fetchProductMovement(
      query: query,
      branch: branch,
      from: from,
      to: to,
      movementType: movementType,
    );

    return rows.map((e) {
      final movementDate =
          DateTime.tryParse((e['movement_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final createdAt =
          DateTime.tryParse((e['created_at'] ?? '').toString()) ?? movementDate;

      return ProductMovement(
        branch: (e['branch'] ?? '').toString(),
        itemCode: (e['item_code'] ?? '').toString(),
        itemName: (e['item_name'] ?? '').toString(),
        barcode: e['barcode'] ?? '',
        movementType: (e['movement_type'] ?? '').toString(),
        qty: e['qty'] ?? 0,
        movementDate: movementDate,
        createdAt: createdAt.toLocal(),
      );
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDailyOrderForBranch({
    required String branch,
    required String runDate,
  }) {
    return remote.fetchDailyOrderForBranch(branch: branch, runDate: runDate);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDailyOrdersForBranches({
    required List<String> branches,
    required String runDate,
  }) {
    return remote.fetchDailyOrdersForBranches(
      branches: branches,
      runDate: runDate,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDailyOrderMovementsForBranches({
    required List<String> branches,
    required String runDate,
  }) {
    return remote.fetchDailyOrderMovementsForBranches(
      branches: branches,
      runDate: runDate,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBranchOrderMovements({
    required String branch,
    required DateTime date,
    required String query,
  }) {
    return remote.fetchBranchOrderMovements(
      branch: branch,
      date: date,
      query: query,
    );
  }
}
