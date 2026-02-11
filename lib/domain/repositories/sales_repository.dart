abstract class SalesRepository {
  Future<Map<String, num>> fetchDemand30ByItemCode({
    required String branchName,
  });
}
