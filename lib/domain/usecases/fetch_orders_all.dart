import '../entities/daily_order_row.dart';
import '../repositories/orders_repository.dart';

class FetchOrdersAll {
  final OrdersRepository repo;
  const FetchOrdersAll(this.repo);

  Future<List<DailyOrderRow>> call({
    required String runDate,
    required String branchName,
    int batchSize = 5000,
    void Function(int loaded)? onProgress, // ✅ NEW
  }) {
    return repo.fetchOrdersAll(
      runDate: runDate,
      branchName: branchName,
      batchSize: batchSize,
      onProgress: onProgress,
    );
  }
}
