import '../entities/product_info.dart';
import '../repositories/orders_repository.dart';

class FetchProductInfoBatch {
  final OrdersRepository repo;
  FetchProductInfoBatch(this.repo);

  Future<Map<String, ProductInfo>> call({
    required List<String> itemCodes,
    required String branchName,
    required String runDate,
  }) {
    return repo.fetchProductInfoBatch(
      itemCodes: itemCodes,
      branchName: branchName,
      runDate: runDate,
    );
  }
}
