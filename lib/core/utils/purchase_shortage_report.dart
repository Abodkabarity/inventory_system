/// Shared naming contract with automation/purchase_shortage_export.py.
class PurchaseShortageReport {
  static const bucket = 'shotrage purchase';

  static String today({DateTime? now}) {
    final dubai = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 4));
    return '${dubai.year}-${_two(dubai.month)}-${_two(dubai.day)}';
  }

  static String fileName(String runDate) {
    final date = DateTime.parse(runDate);
    return 'Items Shortage Include Assortment '
        '${_two(date.day)}-${_two(date.month)}-${date.year}.xlsx';
  }

  static String storagePath(String runDate) {
    final date = DateTime.parse(runDate);
    return '${_two(date.month)}-${date.year}/${fileName(runDate)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
