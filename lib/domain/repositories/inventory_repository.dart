import '../entities/additional_request_group.dart';
import '../entities/inventory_edit_item.dart';
import '../entities/mismatch_item.dart';

abstract class InventoryRepository {
  Future<List<String>> fetchBranchesToday();

  Future<List<String>> fetchSubmittedBranches(String runDate);

  Future<List<InventoryEditItem>> fetchBranchEdits({
    required String runDate,
    required String branch,
  });

  Future<List<AdditionalRequestGroup>> fetchAdditionalRequests();

  Future<int> fetchAdditionalToday();

  Future<int> fetchAdditionalMonth();

  Future<void> approveInventory({required String id, required num qty});
  Future<Map<String, int>> fetchBranchEditsCount(String runDate);
  Future<Map<String, int>> fetchAdditionalTodayByBranch(String runDate);
  Future<int> fetchAdditionalMonthByBranch(String branch);

  Future<int> fetchAdditionalTodayByBranchExact(String branch);
  Future<List<MismatchItem>> fetchMismatch();
  Future<List<Map<String, dynamic>>> fetchMismatchHistory(
    String branch,
    String itemCode,
  );
  Future<int> fetchMismatchToday();
  Future<int> fetchMismatchMonth();
  Future<int> fetchMismatchTotal();
  Future<num> fetchMismatchDiffSum();
  Future<List<Map<String, dynamic>>> fetchMismatchTracker({
    required DateTime from,
    required DateTime to,
    String? branch,
  });
  Future<void> approveAllInventory(List<Map<String, dynamic>> items);
  Future<void> storeApprove(List<Map<String, dynamic>> items);
  Future<List<Map<String, dynamic>>> fetchAllOrders(
    String runDate, {
    void Function(int loaded)? onProgress,
  });
  Future<List<Map<String, dynamic>>> fetchBranchAllChanges(String branch);
  Future<List<Map<String, dynamic>>> fetchMaxAdjustment();
  Future<List<Map<String, dynamic>>> fetchMaxAdjustmentHistory(
    String itemCode,
    String branch,
  );
  Future<List<Map<String, dynamic>>> fetchMaxAdjExport();
  Future<List<Map<String, dynamic>>> fetchMaxAdjLogExport();
  Future<bool> importMaxAdjRow({
    required Map<String, dynamic> data,
    required bool forceApply,
  });
  Future<bool> checkIfExists({
    required String itemCode,
    required String branch,
  });
  Future<Map<String, dynamic>> getMaxAdj({
    required String itemCode,
    required String branch,
  });
  Future<List<Map<String, dynamic>>> fetchAssortment();

  Future<List<Map<String, dynamic>>> fetchAssortmentHistory(
    String itemCode,
    String branch,
  );
  Future<List<Map<String, dynamic>>> fetchAssortmentExport();
  Future<List<Map<String, dynamic>>> fetchAssortmentLogExport();
  Future<bool> importAssortmentRow({
    required Map<String, dynamic> data,
    required bool forceApply,
  });
  Future<List<Map<String, dynamic>>> fetchTma();

  Future<List<Map<String, dynamic>>> fetchTmaHistory(
    String itemCode,
    String branch,
  );

  Future<List<Map<String, dynamic>>> fetchTmaExport();
  Future<List<Map<String, dynamic>>> fetchTmaLogExport();

  Future<bool> importTmaRow({
    required Map<String, dynamic> data,
    required bool forceApply,
  });
  Future<List<Map<String, dynamic>>> fetchFormulary();

  Future<List<Map<String, dynamic>>> fetchFormularyHistory(
    String itemCode,
    String branch,
  );

  Future<String> fetchFormularyExportCsv();
  Future<String> fetchFormularyLogExportCsv();
  Future<bool> importFormularyRow({
    required Map<String, dynamic> data,
    required bool forceApply,
  });
  Future<Map<String, dynamic>> fetchMismatchStats(String branch);
  Future<List<Map<String, dynamic>>> fetchMismatchExport({
    Function(double progress)? onProgress,
  });
  Future<List<Map<String, dynamic>>> fetchMismatchLogExport();
  Future<void> deleteFormularyRow({
    required String itemCode,
    required String branch,
  });
  Future<void> deleteAssortmentRow({
    required String itemCode,
    required String branch,
  });
  Future<void> deleteTmaRow({required String itemCode, required String branch});
  Future<void> deleteMaxAdjRow({
    required String itemCode,
    required String branch,
  });
  Future<List<Map<String, dynamic>>> fetchOrdersPage({
    required String runDate,
    required int from,
    required int to,
  });

  Future<List<Map<String, dynamic>>> searchOrders({
    required String runDate,
    required String query,
  });
  Future<void> importAssortmentBulk(List<Map<String, dynamic>> rows);
  Future<void> deleteAssortmentBulk(List<Map<String, dynamic>> rows);
  Future<void> importTmaBulk(List<Map<String, dynamic>> rows);

  Future<void> deleteTmaBulk(List<Map<String, dynamic>> rows);
  Future<void> importMaxAdjBulk(List<Map<String, dynamic>> rows);
  Future<void> deleteMaxAdjBulk(List<Map<String, dynamic>> rows);
}
