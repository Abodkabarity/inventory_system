import '../repositories/orders_repository.dart';

class GenerateAllOrders {
  final OrdersRepository repo;
  GenerateAllOrders(this.repo);

  Future<String> call({required String runDate}) {
    return repo.generateAllOrders(runDate: runDate);
  }
}
