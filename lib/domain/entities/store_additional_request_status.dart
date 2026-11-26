/// Status is derived from every eligible line, never from its display order.
class StoreAdditionalRequestStatus {
  StoreAdditionalRequestStatus(Iterable<Map<String, dynamic>> rows)
    : items = rows.where(eligible).toList();

  final List<Map<String, dynamic>> items;

  static String status(Map<String, dynamic> item) =>
      (item['status'] ?? '').toString().trim().toLowerCase();
  static String storeStatus(Map<String, dynamic> item) =>
      (item['store_status'] ?? '').toString().trim().toLowerCase();
  static bool eligible(Map<String, dynamic> item) =>
      item['inventory_qty'] == null ||
      (num.tryParse(item['inventory_qty'].toString()) ?? 0) > 0;
  static bool finished(Map<String, dynamic> item) =>
      status(item) == 'done' || status(item) == 'rejected';
  static bool waiting(Map<String, dynamic> item) =>
      status(item) == 'sent_to_store' && storeStatus(item).isEmpty;
  static bool processing(Map<String, dynamic> item) =>
      status(item) == 'sent_to_store' && storeStatus(item) == 'processing';

  List<Map<String, dynamic>> get pending => items.where(waiting).toList();
  List<Map<String, dynamic>> get printed => items.where(processing).toList();
  int get doneCount => items.where((item) => status(item) == 'done').length;
  int get rejectedCount =>
      items.where((item) => status(item) == 'rejected').length;
  bool get complete => items.isNotEmpty && items.every(finished);
  bool get allRejected =>
      items.isNotEmpty && items.every((item) => status(item) == 'rejected');
  List<Map<String, dynamic>> get printable =>
      (pending.isNotEmpty ? pending : printed)
          .where(
            (item) =>
                (num.tryParse(
                      (item['inventory_qty'] ?? item['request_qty'] ?? 0)
                          .toString(),
                    ) ??
                    0) >
                0,
          )
          .toList();
  String get label => items.isEmpty
      ? 'No approved items'
      : complete
      ? (allRejected ? 'Rejected' : 'Done')
      : pending.isNotEmpty
      ? 'Pending'
      : printed.isNotEmpty
      ? 'Processing'
      : 'Awaiting review';
}
