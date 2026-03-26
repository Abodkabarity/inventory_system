import '../../domain/entities/additional_request_group.dart';
import '../../domain/entities/inventory_edit_item.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/remote/inventory_remote_ds.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  final InventoryRemoteDs remote;

  InventoryRepositoryImpl(this.remote);

  /// ================================
  /// BRANCHES TODAY
  /// ================================
  @override
  Future<List<String>> fetchBranchesToday() async {
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
  /// ORDER EDITS
  /// ================================
  @override
  Future<List<InventoryEditItem>> fetchBranchEdits({
    required String runDate,
    required String branch,
  }) async {
    final rows = await remote.fetchBranchEdits(
      runDate: runDate,
      branch: branch,
    );

    return rows.map((e) {
      final oldQty = num.tryParse((e['old_qty'] ?? '0').toString()) ?? 0;
      final newQty = num.tryParse((e['new_qty'] ?? '0').toString()) ?? 0;

      return InventoryEditItem(
        itemCode: (e['item_code'] ?? '').toString(),
        itemName: (e['item_name'] ?? '').toString(),
        oldQty: oldQty,
        newQty: newQty,
        diff: num.tryParse((e['diff'] ?? '0').toString()) ?? (newQty - oldQty),
        reason: (e['reason'] ?? '').toString(),
        branch: (e['branch_name'] ?? '').toString(),
        createdAt:
            DateTime.tryParse(e['created_at'].toString()) ?? DateTime.now(),
      );
    }).toList();
  }

  /// ================================
  /// ADDITIONAL REQUESTS
  /// ================================
  @override
  Future<List<AdditionalRequestGroup>> fetchAdditionalRequests() async {
    final rows = await remote.fetchAdditionalRequests();

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final row in rows) {
      final groupId = (row['request_group_id'] ?? '').toString();

      if (groupId.isEmpty) continue;

      grouped.putIfAbsent(groupId, () => []);

      grouped[groupId]!.add(row);
    }

    final List<AdditionalRequestGroup> result = [];

    grouped.forEach((groupId, items) {
      final first = items.first;

      /// run_date هو الصحيح
      DateTime created =
          DateTime.tryParse(first['run_date'].toString()) ?? DateTime.now();

      /// STATUS
      String status = 'pending_inventory';

      if (items.every((e) => e['status'] == 'done')) {
        status = 'done';
      } else if (items.every((e) => e['status'] == 'rejected')) {
        status = 'rejected';
      } else if (items.any((e) => e['status'] == 'sent_to_store')) {
        status = 'sent_to_store';
      }

      /// ITEMS
      final itemCodes = items
          .map((e) => (e['item_code'] ?? '').toString())
          .join(',');

      final itemNames = items
          .map((e) => (e['item_name'] ?? '').toString())
          .join(',');

      result.add(
        AdditionalRequestGroup(
          groupId: groupId,
          branchName: (first['branch_name'] ?? '').toString(),
          createdAt: created,
          itemsCount: items.length,
          status: status,
          itemNames: itemNames,
          itemCodes: itemCodes,
        ),
      );
    });

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return result;
  }

  /// ================================
  /// ADDITIONAL TODAY COUNT
  /// ================================
  @override
  Future<int> fetchAdditionalToday() async {
    return await remote.fetchAdditionalToday();
  }

  /// ================================
  /// ADDITIONAL MONTH COUNT
  /// ================================
  @override
  Future<int> fetchAdditionalMonth() async {
    return await remote.fetchAdditionalMonth();
  }

  /// ================================
  /// INVENTORY APPROVAL
  /// ================================
  @override
  Future<void> approveInventory({required String id, required num qty}) {
    return remote.approveInventory(id: id, qty: qty);
  }

  @override
  Future<Map<String, int>> fetchBranchEditsCount(String runDate) {
    return remote.fetchBranchEditsCount(runDate);
  }

  /// ================================
  /// ADDITIONAL TODAY PER BRANCH
  /// ================================
  @override
  Future<Map<String, int>> fetchAdditionalTodayByBranch(String runDate) async {
    return await remote.fetchAdditionalTodayByBranch(runDate);
  }

  @override
  Future<int> fetchAdditionalMonthByBranch(String branch) {
    return remote.fetchAdditionalMonthByBranch(branch);
  }

  @override
  Future<int> fetchAdditionalTodayByBranchExact(String branch) {
    return remote.fetchAdditionalTodayByBranchExact(branch);
  }
}
