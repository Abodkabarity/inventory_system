import '../repositories/inventory_orders_repository.dart';

class GenerateAllOrders {
  final InventoryOrdersRepository repo;
  GenerateAllOrders(this.repo);

  Future<String> call({required String runDate}) {
    return repo.startGenerateAllOrders(runDate: runDate);
  }
}
