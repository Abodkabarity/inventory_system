import '../repositories/inventory_orders_repository.dart';

class StepGenerateAllOrders {
  final InventoryOrdersRepository repo;
  StepGenerateAllOrders(this.repo);

  Future<Map<String, dynamic>> call({
    required String jobId,
    int chunkSize = 10,
  }) {
    return repo.stepGenerateAllOrders(jobId: jobId, chunkSize: chunkSize);
  }
}
