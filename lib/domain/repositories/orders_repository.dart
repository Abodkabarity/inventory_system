import '../entities/daily_order_row.dart';
import '../entities/product_info.dart';

abstract class OrdersRepository {
  Future<List<DailyOrderRow>> fetchOrdersAll({
    required String runDate,
    required String branchName,
    int batchSize,
    void Function(int loaded)? onProgress,
  });

  Future<Map<String, ProductInfo>> fetchProductInfoBatch({
    required List<String> itemCodes,
    required String branchName,
    required String runDate,
  });

  Future<String> generateBranchOrder({
    required String runDate,
    required String branchName,
  });

  Future<String> generateAllOrders({required String runDate});

  Future<Map<String, dynamic>> stepGenerateAllOrders({
    required String jobId,
    int chunkSize,
  });

  Future<Map<String, dynamic>?> fetchJob({required String jobId});

  // zone
  Future<String> fetchBranchZone({required String branchName});

  // edits + submission
  Future<void> upsertOrderEdits({
    required String runDate,
    required String zone,
    required String branchName,
    required List<Map<String, dynamic>> rows,
  });

  Future<void> upsertSubmission({
    required String runDate,
    required String zone,
    required String branchName,
    required String status,
  });

  Future<String> fetchSubmissionStatus({
    required String runDate,
    required String branchName,
  });

  // additional requests
  Future<void> insertAdditionalRequests({
    required String runDate,
    required String zone,
    required String branchName,
    required List<Map<String, dynamic>> rows,
  });

  Future<Map<String, num>> fetchAdditionalRequestsForBranch({
    required String runDate,
    required String branchName,
  });

  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAdditionalRequestsHistoryForBranch({
    required String runDate,
    required String branchName,
  });

  // tracking list (flat rows with status/fulfilled/store_note)
  Future<List<Map<String, dynamic>>> fetchAdditionalRequestsTrackingForBranch({
    String? runDate,
    required String branchName,
  });
  Future<List<Map<String, dynamic>>> fetchMismatch({required String branch});

  Future<void> insertMismatch(Map<String, dynamic> data);

  Future<void> updateMismatch({
    required String id,
    required num system,
    required num actual,
    required Map old,
  });

  Future<void> deleteMismatch(String id);

  Future<List<Map<String, dynamic>>> searchItemsByCode(String query);

  Future<List<Map<String, dynamic>>> searchItemsByName(String query);
  // ==========================
  // MAX ADJUSTMENT
  // ==========================

  Future<List<Map<String, dynamic>>> fetchMaxAdj({required String branch});

  Future<void> insertMaxAdj(Map<String, dynamic> data);

  Future<void> deleteMaxAdj(String id);
  Future<List<String>> fetchBranchOrderDays({required String branchName});
  Future<num> fetchItemDemand({
    required String branch,
    required String itemCode,
  });
}
