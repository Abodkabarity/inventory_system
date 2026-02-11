import '../repositories/sales_repository.dart';

class GetSalesDemand30Map {
  final SalesRepository repo;
  const GetSalesDemand30Map(this.repo);

  Future<Map<String, num>> call({required String branchName}) {
    return repo.fetchDemand30ByItemCode(branchName: branchName);
  }
}
