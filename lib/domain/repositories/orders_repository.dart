import '../entities/daily_order_row.dart';
import '../entities/product_info.dart';

abstract class OrdersRepository {
  Future<List<DailyOrderRow>> fetchOrdersAll({
    required String runDate,
    required String branchName,
    int batchSize,
    void Function(int loaded)? onProgress, // ✅ NEW
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
}
