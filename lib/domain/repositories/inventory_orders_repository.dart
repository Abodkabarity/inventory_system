abstract class InventoryOrdersRepository {
  Future<String> startGenerateAllOrders({required String runDate});

  Future<Map<String, dynamic>> stepGenerateAllOrders({
    required String jobId,
    int chunkSize,
  });

  Future<Map<String, dynamic>?> fetchJob({required String jobId});

  Future<Map<String, dynamic>> fetchHeadersPage({
    required String runDate,
    required int pageIndex,
    required int pageSize,
  });

  Future<Map<String, dynamic>> fetchItemsPage({
    required String branchName,
    required String runDate,
    required int pageIndex,
    required int pageSize,
  });
}
