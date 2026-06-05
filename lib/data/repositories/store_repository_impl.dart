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
  Future<List<Map<String, dynamic>>> fetchAllBranches() async {
    return await remote.fetchAllBranches();
  }
  @override
  Future<void> markBranchPrinted({
    required String runDate,
    required String branch,
  }) {
    return remote.markBranchPrinted(
      runDate: runDate,
      branch: branch,
    );
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

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final row in rows) {
      final groupId = (row['request_group_id'] ?? '').toString();

      grouped.putIfAbsent(groupId, () => []);
      grouped[groupId]!.add(row);
    }

    final List<AdditionalRequestGroup> result = [];

    grouped.forEach((groupId, items) {

      final first = items.first;

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
      final hasPending = validItems.any(
            (e) => e['status'] == 'sent_to_store',
      );

      final allRejected = validItems.every(
            (e) => e['status'] == 'rejected',
      );

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
      final isProcessing = validItems.any((e) => e['store_status'] == 'processing');
      result.add(
        AdditionalRequestGroup(
          groupId: groupId,
          branchName: (first['branch_name'] ?? '').toString(),
          createdAt: created,
          itemsCount: validItems.length,
          status: status,
          itemNames: '',
          itemCodes: '',
          storeStatus: isProcessing ? 'processing' : null,
          contactLogistic: isUrgent ? 'urgent' : '',
        ),
      );
    });

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return result;
  }

  /// ================================
  /// APPROVE REQUEST
  /// ================================
  @override
  Future<void> approveRequest({required String id, required num qty}) {
    return remote.approveRequest(id: id, qty: qty);
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
      final groupId = row['request_group_id'].toString();

      grouped.putIfAbsent(groupId, () => []);
      grouped[groupId]!.add(row);
    }

    final result = <AdditionalRequestGroup>[];

    grouped.forEach((groupId, items) {
      final first = items.first;

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
      final hasPending = validItems.any(
            (e) => e['status'] == 'sent_to_store',
      );

      final allRejected = validItems.every(
            (e) => e['status'] == 'rejected',
      );

      String status;

      if (hasPending) {
        status = 'sent_to_store';
      } else if (allRejected) {
        status = 'rejected';
      } else {
        // done OR mixed(done + rejected)
        status = 'done';
      }
      final isProcessing = validItems.any((e) => e['store_status'] == 'processing');
      result.add(
        AdditionalRequestGroup(
          groupId: groupId,
          branchName: first['branch_name'],
          createdAt: DateTime.parse(first['created_at']).toLocal(),
          itemsCount: validItems.length,
          status: status,
          itemNames: itemNames,
          itemCodes: itemCodes,
          storeStatus: isProcessing ? 'processing' : null,
          contactLogistic: (first['contact_logistic'] ?? '').toString(),
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
  Future<void> markAsProcessing(List<String> ids) {
    return remote.markAsProcessing(ids);
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
  Future<List<ProductMovement>> fetchProductMovement({
    required String branch,
    required String itemCode,
  }) async {
    final rows = await remote.fetchProductMovement(
      branch: branch,
      itemCode: itemCode,
    );

    return rows.map((e) {
      return ProductMovement(
        branch: e['branch'],
        itemCode: e['item_code'],
        itemName: e['item_name'],
        barcode: e['barcode'] ?? '',
        movementType: e['movement_type'],
        qty: e['qty'] ?? 0,
        createdAt: DateTime.parse(e['created_at']).toLocal(),
      );
    }).toList();
  }
}
