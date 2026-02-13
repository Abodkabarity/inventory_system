import '../repositories/inventory_orders_repository.dart';

class LoadHeadersPage {
  final InventoryOrdersRepository repo;
  LoadHeadersPage(this.repo);

  Future<List<Map<String, dynamic>>> call({
    required String runDate,
    required int pageIndex,
    required int pageSize,
  }) async {
    final out = await repo.fetchHeadersPage(
      runDate: runDate,
      pageIndex: pageIndex,
      pageSize: pageSize,
    );
    return (out['rows'] as List).cast<Map<String, dynamic>>();
  }
}
