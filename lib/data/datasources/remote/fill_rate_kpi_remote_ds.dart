import 'package:supabase_flutter/supabase_flutter.dart';

class FillRateKpiRemoteDs {
  final SupabaseClient client;

  const FillRateKpiRemoteDs(this.client);

  Future<FillRateReport> fetchReport({
    required DateTime from,
    required DateTime to,
    String? branch,
    int detailLimit = 1000,
  }) async {
    final response = await client.rpc(
      'get_fill_rate_report_v1',
      params: {..._params(from, to, branch), 'p_detail_limit': detailLimit},
    );
    final payload = Map<String, dynamic>.from(response as Map);
    final items = await _withCurrentPurchaseStatuses(
      _rows(payload['items']).map(FillRateItem.fromMap).toList(),
    );
    return FillRateReport(
      summaries: _rows(
        payload['summaries'],
      ).map(FillRateSummary.fromMap).toList(),
      daily: _rows(payload['daily']).map(FillRateDaily.fromMap).toList(),
      statuses: _rows(payload['statuses']).map(FillRateStatus.fromMap).toList(),
      items: items,
    );
  }

  Future<List<FillRateItem>> fetchAllItems({
    required DateTime from,
    required DateTime to,
    String? branch,
    void Function(double progress)? onProgress,
  }) async {
    const pageSize = 5000;
    final result = <FillRateItem>[];
    var offset = 0;
    var total = 1;
    while (offset < total) {
      final response = await client.rpc(
        'get_fill_rate_items_v1',
        params: {
          ..._params(from, to, branch),
          'p_offset': offset,
          'p_limit': pageSize,
        },
      );
      final rows = _rows(response);
      if (rows.isEmpty) break;
      total = _integer(rows.first['total_count']);
      result.addAll(
        await _withCurrentPurchaseStatuses(
          rows.map(FillRateItem.fromMap).toList(growable: false),
        ),
      );
      offset += rows.length;
      onProgress?.call(total == 0 ? 1 : (offset / total).clamp(0, 1));
      await Future<void>.delayed(Duration.zero);
    }
    return result;
  }

  Future<FillRateItemPage> fetchItemsPage({
    required DateTime from,
    required DateTime to,
    String? branch,
    required int offset,
    int limit = 200,
  }) async {
    final response = await client.rpc(
      'get_fill_rate_items_v1',
      params: {
        ..._params(from, to, branch),
        'p_offset': offset,
        'p_limit': limit,
      },
    );
    final rows = _rows(response);
    final items = await _withCurrentPurchaseStatuses(
      rows.map(FillRateItem.fromMap).toList(growable: false),
    );
    return FillRateItemPage(
      items: items,
      totalCount: rows.isEmpty ? 0 : _integer(rows.first['total_count']),
    );
  }

  Future<List<FillRateItem>> _withCurrentPurchaseStatuses(
    List<FillRateItem> items,
  ) async {
    if (items.isEmpty) return items;

    const batchSize = 300;
    final codes = items
        .map((item) => item.itemCode.trim())
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final statusByCode = <String, String>{};

    for (var start = 0; start < codes.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, codes.length);
      final response = await client
          .from('availability_kpi_purchase_status')
          .select('item_code,status_name')
          .inFilter('item_code', codes.sublist(start, end));
      for (final row in List<Map<String, dynamic>>.from(response as List)) {
        final code = '${row['item_code'] ?? ''}'.trim();
        final status = '${row['status_name'] ?? ''}'.trim();
        if (code.isNotEmpty && status.isNotEmpty) {
          statusByCode[code] = status;
        }
      }
    }

    return items
        .map((item) {
          final currentStatus = statusByCode[item.itemCode.trim()];
          return currentStatus == null
              ? item
              : item.withPurchaseStatus(currentStatus);
        })
        .toList(growable: false);
  }

  static Map<String, dynamic> _params(
    DateTime from,
    DateTime to,
    String? branch,
  ) => {
    'p_date_from': _date(from),
    'p_date_to': _date(to),
    'p_branch': branch == null || branch == 'ALL BRANCHES' ? null : branch,
  };
}

class FillRateItemPage {
  final List<FillRateItem> items;
  final int totalCount;

  const FillRateItemPage({required this.items, required this.totalCount});
}

class FillRateReport {
  final List<FillRateSummary> summaries;
  final List<FillRateDaily> daily;
  final List<FillRateStatus> statuses;
  final List<FillRateItem> items;

  const FillRateReport({
    required this.summaries,
    required this.daily,
    required this.statuses,
    required this.items,
  });

  FillRateSummary get total => summaries.firstWhere(
    (value) => value.branchName == 'ALL BRANCHES',
    orElse: () => FillRateSummary.empty('ALL BRANCHES'),
  );
}

class FillRateSummary {
  final String branchName;
  final int totalItems;
  final int suppliedItems;
  final int fullySupplied;
  final int partiallySupplied;
  final int notSupplied;
  final num requiredQty;
  final num suppliedQty;
  final num lineFillRate;
  final num unitFillRate;

  const FillRateSummary({
    required this.branchName,
    required this.totalItems,
    required this.suppliedItems,
    required this.fullySupplied,
    required this.partiallySupplied,
    required this.notSupplied,
    required this.requiredQty,
    required this.suppliedQty,
    required this.lineFillRate,
    required this.unitFillRate,
  });

  factory FillRateSummary.fromMap(Map<String, dynamic> map) => FillRateSummary(
    branchName: '${map['branch_name'] ?? ''}',
    totalItems: _integer(map['total_items']),
    suppliedItems: _integer(map['supplied_items']),
    fullySupplied: _integer(map['fully_supplied']),
    partiallySupplied: _integer(map['partially_supplied']),
    notSupplied: _integer(map['not_supplied']),
    requiredQty: _number(map['required_qty']),
    suppliedQty: _number(map['supplied_qty']),
    lineFillRate: _number(map['line_fill_rate']),
    unitFillRate: _number(map['unit_fill_rate']),
  );

  factory FillRateSummary.empty(String branch) => FillRateSummary(
    branchName: branch,
    totalItems: 0,
    suppliedItems: 0,
    fullySupplied: 0,
    partiallySupplied: 0,
    notSupplied: 0,
    requiredQty: 0,
    suppliedQty: 0,
    lineFillRate: 0,
    unitFillRate: 0,
  );
}

class FillRateDaily {
  final DateTime date;
  final int totalItems;
  final int suppliedItems;
  final int fullySupplied;
  final int partiallySupplied;
  final int notSupplied;
  final num lineFillRate;
  final num unitFillRate;

  const FillRateDaily({
    required this.date,
    required this.totalItems,
    required this.suppliedItems,
    required this.fullySupplied,
    required this.partiallySupplied,
    required this.notSupplied,
    required this.lineFillRate,
    required this.unitFillRate,
  });

  factory FillRateDaily.fromMap(Map<String, dynamic> map) => FillRateDaily(
    date: DateTime.parse('${map['run_date']}'),
    totalItems: _integer(map['total_items']),
    suppliedItems: _integer(map['supplied_items']),
    fullySupplied: _integer(map['fully_supplied']),
    partiallySupplied: _integer(map['partially_supplied']),
    notSupplied: _integer(map['not_supplied']),
    lineFillRate: _number(map['line_fill_rate']),
    unitFillRate: _number(map['unit_fill_rate']),
  );
}

class FillRateStatus {
  final String name;
  final int totalItems;
  final int suppliedItems;
  final num share;
  final num lineFillRate;
  final num unitFillRate;
  final num requiredQty;
  final num suppliedQty;

  const FillRateStatus({
    required this.name,
    required this.totalItems,
    required this.suppliedItems,
    required this.share,
    required this.lineFillRate,
    required this.unitFillRate,
    this.requiredQty = 0,
    this.suppliedQty = 0,
  });

  factory FillRateStatus.fromMap(Map<String, dynamic> map) => FillRateStatus(
    name: '${map['purchase_status'] ?? 'Not Assigned'}',
    totalItems: _integer(map['total_items']),
    suppliedItems: _integer(map['supplied_items']),
    share: _number(map['status_share']),
    lineFillRate: _number(map['line_fill_rate']),
    unitFillRate: _number(map['unit_fill_rate']),
    requiredQty: _number(map['required_qty']),
    suppliedQty: _number(map['supplied_qty']),
  );
}

/// The management view intentionally measures only products that can be
/// actioned internally: AVAILABLE (including AVAILABLE N.E) and products with
/// no purchase status. Supplier-related statuses are excluded from both rates.
class FillRateFocusedMetrics {
  final int includedItems;
  final int excludedItems;
  final num requiredQty;
  final num suppliedQty;
  final num lineFillRate;
  final num unitFillRate;

  const FillRateFocusedMetrics({
    required this.includedItems,
    required this.excludedItems,
    required this.requiredQty,
    required this.suppliedQty,
    required this.lineFillRate,
    required this.unitFillRate,
  });

  factory FillRateFocusedMetrics.fromStatuses(List<FillRateStatus> statuses) {
    final included = statuses.where((status) => includes(status.name)).toList();
    final includedItems = included.fold<int>(
      0,
      (sum, status) => sum + status.totalItems,
    );
    final allItems = statuses.fold<int>(
      0,
      (sum, status) => sum + status.totalItems,
    );
    final requiredQty = included.fold<num>(
      0,
      (sum, status) => sum + status.requiredQty,
    );
    final suppliedQty = included.fold<num>(
      0,
      (sum, status) => sum + status.suppliedQty,
    );
    final lineFillRate = includedItems == 0
        ? 0
        : included.fold<num>(
                0,
                (sum, status) => sum + status.lineFillRate * status.totalItems,
              ) /
              includedItems;
    final unitFillRate = requiredQty > 0
        ? 100 * suppliedQty / requiredQty
        : includedItems == 0
        ? 0
        : included.fold<num>(
                0,
                (sum, status) => sum + status.unitFillRate * status.totalItems,
              ) /
              includedItems;

    return FillRateFocusedMetrics(
      includedItems: includedItems,
      excludedItems: (allItems - includedItems).clamp(0, allItems),
      requiredQty: requiredQty,
      suppliedQty: suppliedQty,
      lineFillRate: lineFillRate,
      unitFillRate: unitFillRate,
    );
  }

  static bool includes(String status) {
    final value = status.trim().toUpperCase();
    return value == 'AVAILABLE' ||
        value.startsWith('AVAILABLE ') ||
        value.isEmpty ||
        value == 'NOT ASSIGNED' ||
        value == 'NO PURCHASE STATUS';
  }
}

class FillRateItem {
  final int totalCount;
  final DateTime date;
  final String branchName;
  final String itemCode;
  final String itemName;
  final num originalQty;
  final num requiredQty;
  final bool wasEdited;
  final num transferredQty;
  final num suppliedQty;
  final num fillRate;
  final String fulfillmentStatus;
  final String purchaseStatus;

  const FillRateItem({
    required this.totalCount,
    required this.date,
    required this.branchName,
    required this.itemCode,
    required this.itemName,
    required this.originalQty,
    required this.requiredQty,
    required this.wasEdited,
    required this.transferredQty,
    required this.suppliedQty,
    required this.fillRate,
    required this.fulfillmentStatus,
    required this.purchaseStatus,
  });

  factory FillRateItem.fromMap(Map<String, dynamic> map) => FillRateItem(
    totalCount: _integer(map['total_count']),
    date: DateTime.parse('${map['run_date']}'),
    branchName: '${map['branch_name'] ?? ''}',
    itemCode: '${map['item_code'] ?? ''}',
    itemName: '${map['item_name'] ?? ''}',
    originalQty: _number(map['original_qty']),
    requiredQty: _number(map['required_qty']),
    wasEdited: map['was_edited'] == true,
    transferredQty: _number(map['transferred_qty']),
    suppliedQty: _number(map['supplied_qty']),
    fillRate: _number(map['fill_rate']),
    fulfillmentStatus: '${map['fulfillment_status'] ?? ''}',
    purchaseStatus: '${map['purchase_status'] ?? 'Not Assigned'}',
  );

  FillRateItem withPurchaseStatus(String value) => FillRateItem(
    totalCount: totalCount,
    date: date,
    branchName: branchName,
    itemCode: itemCode,
    itemName: itemName,
    originalQty: originalQty,
    requiredQty: requiredQty,
    wasEdited: wasEdited,
    transferredQty: transferredQty,
    suppliedQty: suppliedQty,
    fillRate: fillRate,
    fulfillmentStatus: fulfillmentStatus,
    purchaseStatus: value,
  );
}

List<Map<String, dynamic>> _rows(dynamic value) =>
    List<Map<String, dynamic>>.from((value as List?) ?? const []);
num _number(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
int _integer(dynamic value) => _number(value).toInt();
String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
