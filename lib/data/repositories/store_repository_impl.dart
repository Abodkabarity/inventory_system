import '../../domain/entities/additional_request_group.dart';
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
  Future<List<String>> fetchAllBranches() async {
    final rows = await remote.fetchBranchesToday();
    return rows;
  }

  /// ================================
  /// SUBMITTED BRANCHES
  /// ================================
  @override
  Future<List<String>> fetchSubmittedBranches(String runDate) async {
    final rows = await remote.fetchSubmittedBranches(runDate);
    return rows;
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
        created = DateTime.now();
      } else {
        created = DateTime.tryParse(createdRaw.toString()) ?? DateTime.now();
      }

      final validItems = items.where((e) {
        final inv = e['inventory_qty'];

        if (inv == null) return true;
        return inv > 0;
      }).toList();

      String status;

      if (items.every((e) => e['status'] == 'done')) {
        status = 'done';
      } else if (items.every((e) => e['status'] == 'rejected')) {
        status = 'rejected';
      } else {
        status = 'sent_to_store';
      }

      result.add(
        AdditionalRequestGroup(
          groupId: groupId,
          branchName: (first['branch_name'] ?? '').toString(),
          createdAt: created,
          itemsCount: validItems.length,
          status: status,
          itemNames: '',
          itemCodes: '',
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

      String status;

      if (items.every((e) => e['status'] == 'done')) {
        status = 'done';
      } else if (items.every((e) => e['status'] == 'rejected')) {
        status = 'rejected';
      } else {
        status = 'sent_to_store';
      }

      result.add(
        AdditionalRequestGroup(
          groupId: groupId,
          branchName: first['branch_name'],
          createdAt: DateTime.parse(first['created_at']),
          itemsCount: validItems.length,
          status: status,
          itemNames: itemNames,
          itemCodes: itemCodes,
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
}
