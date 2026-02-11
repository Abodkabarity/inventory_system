import '../../domain/entities/item_report_row.dart';
import '../../domain/repositories/item_report_repo.dart';
import '../datasources/remote/item_report_remote_ds.dart';

class ItemReportRepoImpl implements ItemReportRepo {
  final ItemReportRemoteDs remote;
  ItemReportRepoImpl(this.remote);

  @override
  Future<int> getTotalCount() => remote.getTotalCountSlowButCompatible();

  @override
  Future<List<ItemReportRow>> fetchPage({required int from, required int to}) =>
      remote.fetchPage(from: from, to: to);
}
