import '../../domain/entities/additional_request_group.dart';
import '../../domain/entities/store_order_item.dart';
import '../../domain/repositories/store_repository.dart';
import '../datasources/remote/store_remote_ds.dart';

class StoreRepositoryImpl implements StoreRepository {
  final StoreRemoteDs remote;

  StoreRepositoryImpl(this.remote);

  /// =========================================
  /// FIX BARCODE FORMAT (NO SCIENTIFIC FORMAT)
  /// =========================================
  String _formatBarcode(dynamic value) {
    if (value == null) return '';

    if (value is int) {
      return value.toString();
    }

    if (value is double) {
      return value.toStringAsFixed(0);
    }

    final s = value.toString();

    if (s.contains('E+') || s.contains('e+')) {
      final d = double.tryParse(s);
      if (d != null) {
        return d.toStringAsFixed(0);
      }
    }

    return s.replaceAll('.0', '');
  }

  /// ================================
  /// ALL BRANCHES
  /// ================================
  @override
  Future<List<String>> fetchAllBranches() async {
    final rows = await remote.fetchBranchesToday();
    return rows;
  }

  /// ================================
  /// SUBMITTED BRANCHES
  /// ================================
  @override
  Future<List<String>> fetchSubmittedBranches(String runDate) async {
    final rows = await remote.fetchSubmittedBranches(runDate);
    return rows;
  }

  /// ================================
  /// BRANCH ITEMS
  /// ================================
  @override
  Future<List<StoreOrderItem>> fetchBranchItems({
    required String runDate,
    required String branch,
  }) async {
    final rows = await remote.fetchBranchItems(
      runDate: runDate,
      branch: branch,
    );

    return rows.map((e) {
      return StoreOrderItem(
        itemCode: (e['item_code'] ?? '').toString(),
        itemName: (e['item_name'] ?? '').toString(),

        /// FIXED BARCODE
        barcode: _formatBarcode(e['barcode']),

        supplier: (e['supplier'] ?? '').toString(),
        classification: (e['store_item_classifications'] ?? '').toString(),
        category: (e['category'] ?? '').toString(),

        quantity:
            num.tryParse(
              (e['final_reorder_qty_store_stock_gt_0'] ?? '0').toString(),
            ) ??
            0,
      );
    }).toList();
  }

  /// ================================
  /// ADDITIONAL REQUESTS
  /// ================================
  @override
  Future<List<AdditionalRequestGroup>> fetchAdditionalRequests(
    String runDate,
  ) async {
    final rows = await remote.fetchAdditionalRequestGroups(runDate: runDate);

    return rows.map((e) {
      final groupId = (e['request_group_id'] ?? '').toString();

      DateTime created;
      final createdRaw = e['created_at'];

      if (createdRaw == null) {
        created = DateTime.now();
      } else {
        created = DateTime.tryParse(createdRaw.toString()) ?? DateTime.now();
      }

      final itemsRaw = e['items_count'];
      int itemsCount;

      if (itemsRaw == null) {
        itemsCount = 0;
      } else if (itemsRaw is int) {
        itemsCount = itemsRaw;
      } else if (itemsRaw is double) {
        itemsCount = itemsRaw.toInt();
      } else {
        itemsCount = int.tryParse(itemsRaw.toString()) ?? 0;
      }

      final doneRaw = e['done'];
      bool done;

      if (doneRaw == null) {
        done = false;
      } else if (doneRaw is bool) {
        done = doneRaw;
      } else {
        done = doneRaw.toString() == 'true';
      }

      return AdditionalRequestGroup(
        groupId: groupId,
        branchName: (e['branch_name'] ?? '').toString(),
        createdAt: created,
        itemsCount: itemsCount,
        done: done,
      );
    }).toList();
  }

  /// ================================
  /// APPROVE REQUEST
  /// ================================
  @override
  Future<void> approveRequest({required String id, required num qty}) {
    return remote.approveRequest(id: id, qty: qty);
  }
}
