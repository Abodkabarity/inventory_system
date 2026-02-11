import '../repositories/stock_repository.dart';

class GetStockMapsForBranch {
  final StockRepository repo;
  const GetStockMapsForBranch(this.repo);

  Future<StockMaps> call({
    required String branchName,
    required String storeName,
  }) async {
    final storeStock = await repo.fetchStoreStockByItemCode(
      storeName: storeName,
    );
    final mismatch = await repo.fetchMismatchDiffByItemCode(
      branchName: branchName,
    );
    final pending = await repo.fetchPendingQtyByItemCode(
      branchName: branchName,
    );
    final branchStockFinal = await repo.buildBranchStockFinalByItemCode(
      branchName: branchName,
    );

    return StockMaps(
      storeStockByItemCode: storeStock,
      mismatchDiffByItemCode: mismatch,
      pendingByItemCode: pending,
      branchStockFinalByItemCode: branchStockFinal,
    );
  }
}

class StockMaps {
  final Map<String, num> storeStockByItemCode;
  final Map<String, num> mismatchDiffByItemCode;
  final Map<String, num> pendingByItemCode;
  final Map<String, num> branchStockFinalByItemCode;

  const StockMaps({
    required this.storeStockByItemCode,
    required this.mismatchDiffByItemCode,
    required this.pendingByItemCode,
    required this.branchStockFinalByItemCode,
  });
}
