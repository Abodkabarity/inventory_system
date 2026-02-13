import '../repositories/inventory_orders_repository.dart';

class LoadItemsPage {
  final InventoryOrdersRepository repo;
  LoadItemsPage(this.repo);

  Future<List<Map<String, dynamic>>> call({
    required String branchName,
    required String runDate,
    required int pageIndex,
    required int pageSize,
  }) async {
    final out = await repo.fetchItemsPage(
      branchName: branchName,
      runDate: runDate,
      pageIndex: pageIndex,
      pageSize: pageSize,
    );

    return (out['rows'] as List).cast<Map<String, dynamic>>();
  }
}
