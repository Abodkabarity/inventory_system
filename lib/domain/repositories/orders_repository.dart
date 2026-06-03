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
// branch info
  Future<Map<String, dynamic>> fetchBranchInfo({
    required String branchName,
  });
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
  Future<void> upsertMaxAdjFromFinalReorder({
    required String branchName,
    required String itemCode,
    required String itemName,
    required num oldQty,
    required num newQty,
    required num currentDemand,
    required String reason,
  });
  Future<bool> checkIfOrderExists({
    required String runDate,
    required String branchName,
  });
  Future<void> upsertFinalReorderDraft({
    required String runDate,
    required String branchName,
    required String itemCode,
    required String itemName,
    required int oldQty,
    required int newQty,
    required String reason,
  });

  Future<List<Map<String, dynamic>>> fetchFinalReorderDrafts({
    required String runDate,
    required String branchName,
  });
  Future<void> upsertAdditionalRequestDraft({
    required String runDate,
    required String branchName,
    required String itemCode,
    required String itemName,
    required num requestQty,
    required String reason,
    required bool isUrgent,
  });

  Future<List<Map<String, dynamic>>> fetchAdditionalRequestDrafts({
    required String runDate,
    required String branchName,
  });
  Future<void> deleteAdditionalRequestDraft({required String id});
  Future<bool> isOperationalOrderReady({required String runDate});
  Future<void> createItemToOrder({
    required String runDate,
    required String branchName,
    required String itemCode,
    required String itemName,
    required num qty,
    required String reason,
  });

  Future<List<Map<String, dynamic>>> fetchItemsToOrder({
    required String runDate,
    required String branchName,
  });

  Future<void> deleteItemToOrder({required String id});

  Future<void> markItemToOrderProcessed({required String id});

  Future<void> clearProcessedItemsToOrder({
    required String runDate,
    required String branchName,
  });
  Future<List<Map<String, dynamic>>> searchItemsToOrderSuggestions(
    String query,
  );

  Future<void> updateItemToOrderStatus({
    required String id,
    required String status,
  });
}
