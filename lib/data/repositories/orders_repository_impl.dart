import '../../domain/entities/daily_order_row.dart';
import '../../domain/entities/product_info.dart';
import '../../domain/repositories/orders_repository.dart';
import '../datasources/remote/orders_remote_ds.dart';
import '../models/daily_order_row_model.dart';
import '../models/product_info_model.dart';

class OrdersRepositoryImpl implements OrdersRepository {
  final OrdersRemoteDs remote;
  OrdersRepositoryImpl(this.remote);

  @override
  Future<List<DailyOrderRow>> fetchOrdersAll({
    required String runDate,
    required String branchName,
    int batchSize = 5000,
    void Function(int loaded)? onProgress, // ✅ NEW
  }) async {
    final raw = await remote.fetchOrdersAll(
      runDate: runDate,
      branchName: branchName,
      batchSize: batchSize,
      onProgress: onProgress, // ✅ pass through
    );
    return raw.map(DailyOrderRowModel.fromMap).toList();
  }

  @override
  Future<Map<String, ProductInfo>> fetchProductInfoBatch({
    required List<String> itemCodes,
    required String branchName,
    required String runDate,
  }) async {
    final raw = await remote.fetchProductInfoBatch(itemCodes: itemCodes);

    final out = <String, ProductInfo>{};
    for (final r in raw) {
      final p = ProductInfoModel.fromMap(r);
      out[p.itemCode] = p;
    }
    return out;
  }

  @override
  Future<String> generateBranchOrder({
    required String runDate,
    required String branchName,
  }) {
    return remote.generateBranchOrder(runDate: runDate, branchName: branchName);
  }

  @override
  Future<String> generateAllOrders({required String runDate}) {
    return remote.generateAllOrders(runDate: runDate);
  }

  @override
  Future<Map<String, dynamic>> stepGenerateAllOrders({
    required String jobId,
    int chunkSize = 10,
  }) {
    return remote.stepGenerateAllOrders(jobId: jobId, chunkSize: chunkSize);
  }

  @override
  Future<Map<String, dynamic>?> fetchJob({required String jobId}) {
    return remote.fetchJob(jobId: jobId);
  }
}
