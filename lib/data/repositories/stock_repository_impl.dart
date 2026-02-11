import '../../domain/repositories/stock_repository.dart';
import '../datasources/remote/stock_remote_ds.dart';

class StockRepositoryImpl implements StockRepository {
  final StockRemoteDs remote;
  const StockRepositoryImpl(this.remote);

  @override
  Future<Map<String, num>> fetchLedgerQtyByItemCode({
    required String branchName,
  }) {
    return remote.fetchLedgerQtyMap(branchName: branchName);
  }

  @override
  Future<Map<String, num>> fetchMismatchDiffByItemCode({
    required String branchName,
  }) {
    return remote.fetchMismatchDiffMap(branchName: branchName);
  }

  @override
  Future<Map<String, num>> fetchPendingQtyByItemCode({
    required String branchName,
  }) {
    return remote.fetchPendingQtyMap(branchName: branchName);
  }

  @override
  Future<Map<String, num>> fetchStoreStockByItemCode({
    required String storeName,
  }) {
    return remote.fetchLedgerQtyMap(branchName: storeName);
  }

  @override
  Future<Map<String, num>> buildBranchStockFinalByItemCode({
    required String branchName,
  }) async {
    final ledger = await fetchLedgerQtyByItemCode(branchName: branchName);
    final mismatch = await fetchMismatchDiffByItemCode(branchName: branchName);
    final pending = await fetchPendingQtyByItemCode(branchName: branchName);

    final keys = <String>{}
      ..addAll(ledger.keys)
      ..addAll(mismatch.keys)
      ..addAll(pending.keys);

    final out = <String, num>{};
    for (final k in keys) {
      out[k] = (ledger[k] ?? 0) + (mismatch[k] ?? 0) + (pending[k] ?? 0);
    }
    return out;
  }
}
