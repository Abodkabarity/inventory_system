import '../entities/additional_request_group.dart';
import '../entities/inventory_edit_item.dart';

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
}
