import '../entities/item_report_row.dart';

abstract class ItemReportRepo {
  Future<int> getTotalCount();
  Future<List<ItemReportRow>> fetchPage({required int from, required int to});
}
