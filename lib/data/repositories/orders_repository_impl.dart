import '../../domain/entities/daily_order_row.dart';
import '../../domain/entities/product_info.dart';
import '../../domain/repositories/orders_repository.dart';
import '../datasources/remote/orders_remote_ds.dart';
import '../models/daily_order_row_model.dart';
import '../models/product_info_model.dart';

class OrdersRepositoryImpl implements OrdersRepository {
  final OrdersRemoteDs remote;
  OrdersRepositoryImpl(this.remote);

  @override
  Future<List<DailyOrderRow>> fetchOrdersAll({
    required String runDate,
    required String branchName,
    int batchSize = 2000,
    void Function(int loaded)? onProgress,
  }) async {
    final raw = await remote.fetchOrdersAll(
      runDate: runDate,
      branchName: branchName,
      batchSize: batchSize,
      onProgress: onProgress,
    );
    return raw.map(DailyOrderRowModel.fromMap).toList();
  }

  @override
  Future<Map<String, ProductInfo>> fetchProductInfoBatch({
    required List<String> itemCodes,
    required String branchName,
    required String runDate,
  }) async {
    final raw = await remote.fetchProductInfoBatch(itemCodes: itemCodes);

    final out = <String, ProductInfo>{};
    for (final r in raw) {
      final p = ProductInfoModel.fromMap(r);
      out[p.itemCode] = p;
    }
    return out;
  }

  @override
  Future<String> generateBranchOrder({
    required String runDate,
    required String branchName,
  }) {
    return remote.generateBranchOrder(runDate: runDate, branchName: branchName);
  }

  @override
  Future<String> generateAllOrders({required String runDate}) {
    return remote.generateAllOrders(runDate: runDate);
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
  Future<String> fetchBranchZone({required String branchName}) {
    return remote.fetchBranchZone(branchName: branchName);
  }

  @override
  Future<void> upsertOrderEdits({
    required String runDate,
    required String zone,
    required String branchName,
    required List<Map<String, dynamic>> rows,
  }) {
    return remote.upsertOrderEdits(
      runDate: runDate,
      zone: zone,
      branchName: branchName,
      rows: rows,
    );
  }

  @override
  Future<void> upsertSubmission({
    required String runDate,
    required String zone,
    required String branchName,
    required String status,
  }) {
    return remote.upsertSubmission(
      runDate: runDate,
      zone: zone,
      branchName: branchName,
      status: status,
    );
  }

  @override
  Future<String> fetchSubmissionStatus({
    required String runDate,
    required String branchName,
  }) {
    return remote.fetchSubmissionStatus(
      runDate: runDate,
      branchName: branchName,
    );
  }

  @override
  Future<void> insertAdditionalRequests({
    required String runDate,
    required String zone,
    required String branchName,
    required List<Map<String, dynamic>> rows,
  }) {
    return remote.insertAdditionalRequests(
      runDate: runDate,
      zone: zone,
      branchName: branchName,
      rows: rows,
    );
  }

  @override
  Future<Map<String, num>> fetchAdditionalRequestsForBranch({
    required String runDate,
    required String branchName,
  }) {
    return remote.fetchAdditionalRequestsForBranch(
      runDate: runDate,
      branchName: branchName,
    );
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAdditionalRequestsHistoryForBranch({
    required String runDate,
    required String branchName,
  }) {
    return remote.fetchAdditionalRequestsHistoryForBranch(
      runDate: runDate,
      branchName: branchName,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAdditionalRequestsTrackingForBranch({
    String? runDate,
    required String branchName,
  }) {
    return remote.fetchAdditionalRequestsTrackingForBranch(
      runDate: runDate,
      branchName: branchName,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMismatch({required String branch}) {
    return remote.fetchMismatch(branch: branch);
  }

  @override
  Future<void> insertMismatch(Map<String, dynamic> data) {
    return remote.insertMismatch(data);
  }

  @override
  Future<void> updateMismatch({
    required String id,
    required num system,
    required num actual,
    required Map old,
  }) {
    return remote.updateMismatch(
      id: id,
      system: system,
      actual: actual,
      old: old,
    );
  }

  @override
  Future<void> deleteMismatch(String id) {
    return remote.deleteMismatch(id);
  }

  @override
  Future<List<Map<String, dynamic>>> searchItemsByCode(String query) {
    return remote.searchItemsByCode(query);
  }

  @override
  Future<List<Map<String, dynamic>>> searchItemsByName(String query) {
    return remote.searchItemsByName(query);
  }
  // ==========================
  // MAX ADJ
  // ==========================

  @override
  Future<List<Map<String, dynamic>>> fetchMaxAdj({required String branch}) {
    return remote.fetchMaxAdj(branch: branch);
  }

  @override
  Future<void> insertMaxAdj(Map<String, dynamic> data) {
    return remote.insertMaxAdj(data);
  }

  @override
  Future<void> deleteMaxAdj(String id) {
    return remote.deleteMaxAdj(id);
  }

  @override
  Future<List<String>> fetchBranchOrderDays({required String branchName}) {
    return remote.fetchBranchOrderDays(branchName: branchName);
  }

  @override
  Future<num> fetchItemDemand({
    required String branch,
    required String itemCode,
  }) {
    return remote.fetchItemDemand(branch: branch, itemCode: itemCode);
  }

  @override
  Future<void> upsertMaxAdjFromFinalReorder({
    required String branchName,
    required String itemCode,
    required String itemName,
    required num oldQty,
    required num newQty,
    required num currentDemand,
    required String reason,
  }) {
    return remote.upsertMaxAdjFromFinalReorder(
      branchName: branchName,
      itemCode: itemCode,
      itemName: itemName,
      oldQty: oldQty,
      newQty: newQty,
      currentDemand: currentDemand,
      reason: reason,
    );
  }

  @override
  Future<bool> checkIfOrderExists({
    required String runDate,
    required String branchName,
  }) async {
    print('🔍 CHECK USING RUN DATE: $runDate');

    final res = await remote.client
        .from('daily_order')
        .select('item_code')
        .eq('branch', branchName)
        .eq('run_date', runDate)
        .limit(1);

    print('📦 EXISTS RESULT: ${res.length}');

    return res.isNotEmpty;
  }

  @override
  Future<void> upsertFinalReorderDraft({
    required String runDate,
    required String branchName,
    required String itemCode,
    required String itemName,
    required int oldQty,
    required int newQty,
    required String reason,
  }) {
    return remote.upsertFinalReorderDraft(
      runDate: runDate,
      branchName: branchName,
      itemCode: itemCode,
      itemName: itemName,
      oldQty: oldQty,
      newQty: newQty,
      reason: reason,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFinalReorderDrafts({
    required String runDate,
    required String branchName,
  }) {
    return remote.fetchFinalReorderDrafts(
      runDate: runDate,
      branchName: branchName,
    );
  }

  @override
  Future<void> upsertAdditionalRequestDraft({
    required String runDate,
    required String branchName,
    required String itemCode,
    required String itemName,
    required num requestQty,
    required String reason,
    required bool isUrgent,
  }) {
    return remote.upsertAdditionalRequestDraft(
      runDate: runDate,
      branchName: branchName,
      itemCode: itemCode,
      itemName: itemName,
      requestQty: requestQty,
      reason: reason,
      isUrgent: isUrgent,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAdditionalRequestDrafts({
    required String runDate,
    required String branchName,
  }) {
    return remote.fetchAdditionalRequestDrafts(
      runDate: runDate,
      branchName: branchName,
    );
  }

  @override
  Future<void> deleteAdditionalRequestDraft({required String id}) {
    return remote.deleteAdditionalRequestDraft(id: id);
  }

  @override
  Future<bool> isOperationalOrderReady({required String runDate}) {
    return remote.isOperationalOrderReady(runDate: runDate);
  }
  // ==========================
  // ITEMS TO ORDER
  // ==========================

  @override
  Future<void> createItemToOrder({
    required String runDate,
    required String branchName,
    required String itemCode,
    required String itemName,
    required num qty,
    required String reason,
  }) {
    return remote.createItemToOrder(
      runDate: runDate,
      branchName: branchName,
      itemCode: itemCode,
      itemName: itemName,
      qty: qty,
      reason: reason,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchItemsToOrder({
    required String runDate,
    required String branchName,
  }) {
    return remote.fetchItemsToOrder(runDate: runDate, branchName: branchName);
  }

  @override
  Future<void> deleteItemToOrder({required String id}) {
    return remote.deleteItemToOrder(id: id);
  }

  @override
  Future<void> markItemToOrderProcessed({required String id}) {
    return remote.markItemToOrderProcessed(id: id);
  }

  @override
  Future<void> clearProcessedItemsToOrder({
    required String runDate,
    required String branchName,
  }) {
    return remote.clearProcessedItemsToOrder(
      runDate: runDate,
      branchName: branchName,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> searchItemsToOrderSuggestions(
    String query,
  ) {
    return remote.searchItemsToOrderSuggestions(query);
  }

  @override
  Future<void> updateItemToOrderStatus({
    required String id,
    required String status,
  }) {
    return remote.updateItemToOrderStatus(id: id, status: status);
  }
}
