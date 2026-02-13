import '../repositories/inventory_orders_repository.dart';

class GetOrderJob {
  final InventoryOrdersRepository repo;
  GetOrderJob(this.repo);

  Future<Map<String, dynamic>?> call(String jobId) {
    return repo.fetchJob(jobId: jobId);
  }
}
