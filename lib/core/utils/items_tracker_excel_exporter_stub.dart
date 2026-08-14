import '../../domain/entities/items_tracker_record.dart';

class ItemsTrackerExcelExporter {
  static Future<void> export(List<ItemsTrackerRecord> records) {
    throw UnsupportedError(
      'Item Tracker Excel export is available on web only.',
    );
  }
}
