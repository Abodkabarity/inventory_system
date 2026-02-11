abstract class StockRepository {
  Future<Map<String, num>> fetchLedgerQtyByItemCode({
    required String branchName,
  });

  Future<Map<String, num>> fetchMismatchDiffByItemCode({
    required String branchName,
  });

  Future<Map<String, num>> fetchPendingQtyByItemCode({
    required String branchName,
  });

  Future<Map<String, num>> fetchStoreStockByItemCode({
    required String storeName,
  });

  Future<Map<String, num>> buildBranchStockFinalByItemCode({
    required String branchName,
  });
}
