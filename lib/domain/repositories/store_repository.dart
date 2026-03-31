import '../entities/additional_request_group.dart';
import '../entities/store_order_item.dart';

abstract class StoreRepository {
  Future<List<String>> fetchAllBranches();

  Future<List<String>> fetchSubmittedBranches(String runDate);

  Future<List<StoreOrderItem>> fetchBranchItems({
    required String runDate,
    required String branch,
  });

  Future<List<AdditionalRequestGroup>> fetchAdditionalRequests();
  Future<void> approveRequest({required String id, required num qty});
  Future<List<AdditionalRequestGroup>> fetchAdditionalHistory({
    required DateTime from,
    required DateTime to,
  });
  Future<List<Map<String, dynamic>>> fetchAllSentToStore();

  Future<void> markAsProcessing(List<String> ids);
  Future<List<Map<String, dynamic>>> fetchProcessingRequests();
}
