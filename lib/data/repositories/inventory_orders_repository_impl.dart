import '../../domain/repositories/inventory_orders_repository.dart';
import '../datasources/remote/inventory_orders_remote_ds.dart';

class InventoryOrdersRepositoryImpl implements InventoryOrdersRepository {
  final InventoryOrdersRemoteDs remote;
  InventoryOrdersRepositoryImpl(this.remote);

  @override
  Future<String> startGenerateAllOrders({required String runDate}) {
    return remote.startGenerateAllOrders(runDate: runDate);
  }

  @override
  Future<Map<String, dynamic>> stepGenerateAllOrders({
    required String jobId,
    int chunkSize = 10,
  }) {
    return remote.stepGenerateAllOrders(jobId: jobId, chunkSize: chunkSize);
  }

  @override
  Future<Map<String, dynamic>?> fetchJob({required String jobId}) {
    return remote.fetchJob(jobId: jobId);
  }

  @override
  Future<Map<String, dynamic>> fetchHeadersPage({
    required String runDate,
    required int pageIndex,
    required int pageSize,
  }) {
    return remote.fetchHeadersPage(
      runDate: runDate,
      pageIndex: pageIndex,
      pageSize: pageSize,
    );
  }

  @override
  Future<Map<String, dynamic>> fetchItemsPage({
    required String branchName,
    required String runDate,
    required int pageIndex,
    required int pageSize,
  }) {
    return remote.fetchItemsPage(
      branchName: branchName,
      runDate: runDate,
      pageIndex: pageIndex,
      pageSize: pageSize,
    );
  }
}
