import '../repositories/orders_repository.dart';

class GenerateBranchOrder {
  final OrdersRepository repo;
  GenerateBranchOrder(this.repo);

  Future<String> call({required String runDate, required String branchName}) {
    return repo.generateBranchOrder(runDate: runDate, branchName: branchName);
  }
}
