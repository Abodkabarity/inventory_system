import '../entities/item_report_row.dart';
import '../repositories/item_report_repo.dart';

class ProgressChunk {
  final List<ItemReportRow> items;
  final int loaded;
  final int total;
  const ProgressChunk({
    required this.items,
    required this.loaded,
    required this.total,
  });
}

class LoadItemReportWithProgress {
  final ItemReportRepo repo;
  const LoadItemReportWithProgress(this.repo);

  Stream<ProgressChunk> call({int pageSize = 500}) async* {
    final total = await repo.getTotalCount();
    if (total == 0) {
      yield const ProgressChunk(items: [], loaded: 0, total: 0);
      return;
    }

    int from = 0;
    final all = <ItemReportRow>[];

    while (from < total) {
      final to = (from + pageSize - 1).clamp(0, total - 1);
      final page = await repo.fetchPage(from: from, to: to);
      all.addAll(page);

      yield ProgressChunk(
        items: List.unmodifiable(all),
        loaded: all.length,
        total: total,
      );

      from += pageSize;
    }
  }
}
