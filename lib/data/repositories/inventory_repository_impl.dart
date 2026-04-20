import '../../domain/entities/additional_request_group.dart';
import '../../domain/entities/inventory_edit_item.dart';
import '../../domain/entities/mismatch_item.dart';
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
    final counts = await remote.fetchTodayCounts();
    return rows.map((e) {
      final d = e['daily_order'];
      final key = "${e['item_code']}_${e['branch_name']}";
      return AdditionalRequestGroup(
        groupId: (e['id'] ?? '').toString(),
        branchName: (e['branch_name'] ?? '').toString(),
        createdAt:
            DateTime.tryParse(e['created_at'].toString()) ?? DateTime.now(),

        itemsCount: 1,
        status: (e['status'] ?? 'pending').toString(),
        itemNames: (e['item_name'] ?? '').toString(),
        itemCodes: (e['item_code'] ?? '').toString(),
        contactLogistic: (e['contact_logistic'] ?? '').toString(),
        requestQty: e["request_qty"] ?? 0,

        branchStock: d?['branch_stock'] ?? 0,
        storeStock: d?['store_stock'] ?? 0,
        sales: d?['qty_30_days_from_last_45d'] ?? 0,
        finalReorder: d?['final_reorder_qty_store_stock_gt_0'] ?? "",
        itemStatus: d?['item_purchase_type'] ?? "",
        todayCount: counts[key] ?? 0,
        fulfilledQty: e['fulfilled_qty'] ?? 0,
        storeNote: e['store_note'] ?? '',
        inventoryQty: e['inventory_qty'] ?? 0,
      );
    }).toList();
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

  @override
  Future<List<MismatchItem>> fetchMismatch() async {
    final rows = await remote.fetchMismatch();

    final logs = await remote.client
        .from('mismatch_log')
        .select('branch_name,item_code');

    final logSet = logs
        .map((e) => "${e['branch_name']}_${e['item_code']}")
        .toSet();

    return rows.map((e) {
      final key = "${e['branch_name']}_${e['item_code']}";

      return MismatchItem(
        branchName: e['branch_name'] ?? '',
        itemCode: e['item_code'] ?? '',
        itemName: e['item_name'] ?? '',
        systemStock: e['system_stock'] ?? 0,
        actualStock: e['actual_stock'] ?? 0,
        diff: e['diff'] ?? 0,
        updateDate:
            DateTime.tryParse(e['update_date'].toString()) ?? DateTime.now(),
        hasHistory: logSet.contains(key),
      );
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMismatchHistory(
    String branch,
    String itemCode,
  ) {
    return remote.fetchMismatchLog(branch, itemCode);
  }

  @override
  Future<int> fetchMismatchToday() {
    return remote.fetchMismatchToday();
  }

  @override
  Future<int> fetchMismatchMonth() {
    return remote.fetchMismatchMonth();
  }

  @override
  Future<int> fetchMismatchTotal() {
    return remote.fetchMismatchTotal();
  }

  @override
  Future<num> fetchMismatchDiffSum() {
    return remote.fetchMismatchDiffSum();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMismatchTracker({
    required DateTime from,
    required DateTime to,
    String? branch,
  }) {
    return remote.fetchMismatchTracker(from: from, to: to, branch: branch);
  }

  @override
  Future<void> approveAllInventory(List<Map<String, dynamic>> items) {
    return remote.approveAllInventory(items);
  }

  @override
  Future<void> storeApprove(List<Map<String, dynamic>> items) {
    return remote.storeApprove(items);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAllOrders(String runDate) {
    return remote.fetchOrdersAllInventory(runDate: runDate);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBranchAllChanges(String branch) {
    return remote.fetchBranchAllChanges(branch: branch);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMaxAdjustment() async {
    final res = await remote.client
        .from('max_adj')
        .select()
        .order('update_date', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMaxAdjustmentHistory(
    String itemCode,
    String branch,
  ) async {
    final current = await remote.client
        .from('max_adj')
        .select()
        .eq('item_code', itemCode)
        .eq('branch_name', branch);

    final log = await remote.client
        .from('max_adj_log')
        .select()
        .eq('item_code', itemCode)
        .eq('branch_name', branch);

    return [
      ...current.map((e) => {...e, 'action': 'current'}),
      ...log.map((e) => {...e, 'action': 'log'}),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMaxAdjExport() async {
    final res = await remote.client.from('max_adj').select();
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMaxAdjLogExport() async {
    final res = await remote.client.from('max_adj_log').select();
    print(res);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  @override
  Future<bool> importMaxAdjRow({
    required Map<String, dynamic> data,
    required bool forceApply,
  }) async {
    try {
      final itemCode = (data['item_code'] ?? '').toString().trim();
      final branch = (data['branch_name'] ?? '').toString().trim();

      final existing = await remote.client
          .from('max_adj')
          .select()
          .eq('item_code', itemCode)
          .eq('branch_name', branch);

      if (existing.isNotEmpty) {
        if (!forceApply) {
          return false;
        }

        await remote.client
            .from('max_adj')
            .delete()
            .eq('item_code', itemCode)
            .eq('branch_name', branch);
      }

      await remote.client.from('max_adj').insert({
        ...data,
        'item_code': itemCode,
        'branch_name': branch,
      });

      return true;
    } catch (e) {
      print("ImportMaxAdjRow ERROR: $e");
      return false;
    }
  }

  @override
  Future<bool> checkIfExists({
    required String itemCode,
    required String branch,
  }) async {
    final res = await remote.client
        .from('max_adj')
        .select()
        .eq('item_code', itemCode)
        .eq('branch_name', branch);

    return res.isNotEmpty;
  }
}
