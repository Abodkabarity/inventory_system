import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/date_utils_uae.dart';
import '../domain/entities.dart';

class MobileOrderRemoteDataSource {
  final SupabaseClient client;

  MobileOrderRemoteDataSource(this.client);

  Session? get currentSession => client.auth.currentSession;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      await ensureAllowedUser();
    } on AuthException catch (e) {
      throw Exception(_friendlyAuthMessage(e.message));
    } catch (e) {
      await client.auth.signOut();
      rethrow;
    }
  }

  Future<void> signOut() => client.auth.signOut();

  Future<void> ensureAllowedUser() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw Exception('Login failed. Please check your email and password.');
    }

    final data = await client
        .from('app_users')
        .select('user_id, role, branch_name, is_active')
        .eq('user_id', uid)
        .maybeSingle();

    if (data == null) {
      throw Exception(
        'This account is not registered in app_users. Please ask admin to add mobile access.',
      );
    }

    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    final isActive = (data['is_active'] as bool?) ?? true;

    if (!isActive) {
      throw Exception('This account is inactive. Please contact admin.');
    }

    if (role != 'inventory' && role != 'store') {
      throw Exception(
        'This mobile app is only for Inventory and Store users. Current role: ${role.isEmpty ? 'missing' : role}.',
      );
    }
  }

  String _friendlyAuthMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Invalid email or password.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Email is not confirmed yet.';
    }
    return message;
  }

  Future<List<BranchOption>> fetchBranchesForDate(DateTime date) async {
    final dateText = ymd(date);

    final names = <String>{
      ...await _fetchSubmittedBranchNames(dateText),
      ...await _fetchMovementBranchNames(dateText),
    };

    final sorted = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted.map(BranchOption.new).toList();
  }

  Future<Set<String>> _fetchSubmittedBranchNames(String dateText) async {
    final names = <String>{};
    const pageSize = 1000;
    var from = 0;

    while (true) {
      final rows = await client
          .from('order_submissions')
          .select('branch_name,status')
          .eq('run_date', dateText)
          .order('branch_name')
          .range(from, from + pageSize - 1);

      final page = List<Map<String, dynamic>>.from(rows);
      for (final row in page) {
        if (!_isSubmitted(row['status'])) continue;
        final name = (row['branch_name'] ?? '').toString().trim();
        if (name.isNotEmpty) names.add(name);
      }

      if (page.length < pageSize) break;
      from += pageSize;
    }

    return names;
  }

  Future<Set<String>> _fetchMovementBranchNames(String dateText) async {
    final names = <String>{};
    const pageSize = 1000;
    var from = 0;

    while (true) {
      final rows = await client
          .from('product_movement_history')
          .select('branch,movement_type')
          .eq('movement_date', dateText)
          .order('branch')
          .range(from, from + pageSize - 1);

      final page = List<Map<String, dynamic>>.from(rows);
      for (final row in page) {
        if (!_isDailyOrder(row['movement_type'])) continue;
        final name = (row['branch'] ?? '').toString().trim();
        if (name.isNotEmpty) names.add(name);
      }

      if (page.length < pageSize) break;
      from += pageSize;
    }

    return names;
  }

  Future<List<MobileOrderItem>> fetchBranchOrder({
    required String branch,
    required DateTime date,
  }) async {
    final dateText = ymd(date);
    final movements = <Map<String, dynamic>>[];
    const pageSize = 1000;
    var from = 0;

    while (true) {
      final movementRows = await client
          .from('product_movement_history')
          .select(
            'id,branch,movement_date,item_code,item_name,movement_type,qty,source_id,created_at,store_item_classifications',
          )
          .eq('branch', branch)
          .eq('movement_date', dateText)
          .order('item_code', ascending: true)
          .range(from, from + pageSize - 1);

      final page = List<Map<String, dynamic>>.from(movementRows);
      movements.addAll(
        page.where((row) => _isDailyOrder(row['movement_type'])),
      );
      if (page.length < pageSize) break;
      from += pageSize;
    }

    if (movements.isEmpty) return [];

    final detailByCode = await _fetchDailyOrderDetails(
      branch: branch,
      dateText: dateText,
      itemCodes: movements
          .map((e) => (e['item_code'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(),
    );
    final validBarcodesByCode = await _fetchItemReportBarcodes(
      movements
          .map((e) => (e['item_code'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(),
    );

    final grouped = <String, MobileOrderItem>{};
    for (final row in movements) {
      final itemCode = (row['item_code'] ?? '').toString();
      if (itemCode.isEmpty) continue;
      final details = detailByCode[itemCode] ?? const <String, dynamic>{};
      final qty = _num(row['qty']);
      if (qty <= 0) continue;

      final old = grouped[itemCode];
      if (old == null) {
        grouped[itemCode] = MobileOrderItem(
          movementId: (row['id'] ?? '').toString(),
          branch: (row['branch'] ?? branch).toString(),
          movementDate:
              DateTime.tryParse((row['movement_date'] ?? '').toString()) ??
              date,
          itemCode: itemCode,
          itemName: _firstText([details['item_name'], row['item_name']]),
          barcode: _barcode(details['barcode']),
          validBarcodes: validBarcodesByCode[itemCode] ?? const [],
          supplier: (details['supplier'] ?? '').toString(),
          category: (details['category'] ?? '').toString(),
          classification: _firstText([
            details['store_item_classifications'],
            row['store_item_classifications'],
          ]),
          expectedQty: qty,
          sourceId: (row['source_id'] ?? '').toString(),
        );
      } else {
        grouped[itemCode] = MobileOrderItem(
          movementId: old.movementId,
          branch: old.branch,
          movementDate: old.movementDate,
          itemCode: old.itemCode,
          itemName: old.itemName,
          barcode: old.barcode,
          validBarcodes: old.validBarcodes,
          supplier: old.supplier,
          category: old.category,
          classification: old.classification,
          expectedQty: old.expectedQty + qty,
          sourceId: old.sourceId,
        );
      }
    }

    final items = grouped.values.toList();
    items.sort(_printSort);
    return items;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchDailyOrderDetails({
    required String branch,
    required String dateText,
    required List<String> itemCodes,
  }) async {
    final out = <String, Map<String, dynamic>>{};
    const size = 200;
    for (var i = 0; i < itemCodes.length; i += size) {
      final batch = itemCodes.skip(i).take(size).toList();
      final rows = await client
          .from('daily_order')
          .select(
            'item_code,item_name,barcode,supplier,store_item_classifications,category',
          )
          .eq('branch', branch)
          .eq('run_date', dateText)
          .inFilter('item_code', batch);
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final code = (row['item_code'] ?? '').toString();
        if (code.isNotEmpty) out[code] = row;
      }
    }
    return out;
  }

  Future<Map<String, List<String>>> _fetchItemReportBarcodes(
    List<String> itemCodes,
  ) async {
    final out = <String, List<String>>{};
    const size = 200;
    for (var i = 0; i < itemCodes.length; i += size) {
      final batch = itemCodes.skip(i).take(size).toList();
      final rows = await client
          .from('item_report')
          .select('item_code,all_barcode')
          .inFilter('item_code', batch);

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final code = (row['item_code'] ?? '').toString().trim();
        if (code.isEmpty) continue;
        final barcodes = _barcodeList(row['all_barcode']);
        if (barcodes.isNotEmpty) out[code] = barcodes;
      }
    }
    return out;
  }

  Future<void> submitPickedItems({
    required String branch,
    required DateTime date,
    required String pickerName,
    required PickCategory category,
    required List<MobileOrderItem> items,
    required Map<String, PickedItem> picked,
  }) async {
    final itemByCode = {for (final item in items) item.itemCode: item};
    final pickedRows = picked.values
        .where((pickedItem) => itemByCode.containsKey(pickedItem.itemCode))
        .toList();
    if (pickedRows.isEmpty) {
      throw Exception('No scanned items to upload.');
    }

    final sessionId = await _ensurePickSession(
      branch: branch,
      date: date,
      pickerName: pickerName,
      category: category,
    );

    final rows = <Map<String, dynamic>>[];
    for (final pickedItem in pickedRows) {
      final item = itemByCode[pickedItem.itemCode]!;
      rows.add({
        'session_id': sessionId,
        'branch': branch,
        'movement_date': ymd(date),
        'category': category.label,
        'picker_name': pickerName,
        'item_code': item.itemCode,
        'item_name': item.itemName,
        'expected_qty': item.expectedQty,
        'picked_qty': pickedItem.pickedQty,
        'scanned_barcode': pickedItem.scannedBarcode,
        'item_barcode': item.barcode,
        'is_matched': true,
        'source_id': item.sourceId,
        'product_movement_id': int.tryParse(item.movementId),
      });
    }

    if (rows.isNotEmpty) {
      await _savePickResults(sessionId: sessionId, rows: rows);
    }
  }

  Future<String> _ensurePickSession({
    required String branch,
    required DateTime date,
    required String pickerName,
    required PickCategory category,
  }) async {
    final existing = await client
        .from('mobile_order_pick_sessions')
        .select('id')
        .eq('branch', branch)
        .eq('movement_date', ymd(date))
        .eq('picker_name', pickerName)
        .eq('category', category.label)
        .limit(1);

    final existingRows = List<Map<String, dynamic>>.from(existing);
    if (existingRows.isNotEmpty) {
      return (existingRows.first['id'] ?? '').toString();
    }

    final inserted = await client
        .from('mobile_order_pick_sessions')
        .insert({
          'branch': branch,
          'movement_date': ymd(date),
          'picker_name': pickerName,
          'category': category.label,
          'status': 'in_progress',
        })
        .select('id')
        .single();

    return (inserted['id'] ?? '').toString();
  }

  Future<void> _savePickResults({
    required String sessionId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final existing = await client
        .from('mobile_order_pick_results')
        .select('item_code')
        .eq('session_id', sessionId);

    final existingCodes = List<Map<String, dynamic>>.from(existing)
        .map((row) => (row['item_code'] ?? '').toString())
        .where((code) => code.isNotEmpty)
        .toSet();

    final inserts = <Map<String, dynamic>>[];
    for (final row in rows) {
      final itemCode = (row['item_code'] ?? '').toString();
      if (existingCodes.contains(itemCode)) {
        await client
            .from('mobile_order_pick_results')
            .update(row)
            .eq('session_id', sessionId)
            .eq('item_code', itemCode);
      } else {
        inserts.add(row);
      }
    }

    if (inserts.isNotEmpty) {
      await client.from('mobile_order_pick_results').insert(inserts);
    }
  }

  int _printSort(MobileOrderItem a, MobileOrderItem b) {
    int compare(String x, String y) {
      return x.trim().toLowerCase().compareTo(y.trim().toLowerCase());
    }

    if (a.pickCategory == PickCategory.general &&
        b.pickCategory == PickCategory.general) {
      final byCategory = compare(a.category, b.category);
      if (byCategory != 0) return byCategory;
      final bySupplier = compare(a.supplier, b.supplier);
      if (bySupplier != 0) return bySupplier;
      return compare(a.itemName, b.itemName);
    }

    final byClassification = compare(a.classification, b.classification);
    if (byClassification != 0) return byClassification;
    final bySupplier = compare(a.supplier, b.supplier);
    if (bySupplier != 0) return bySupplier;
    return compare(a.itemName, b.itemName);
  }

  num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse((value ?? '0').toString()) ?? 0;
  }

  bool _isSubmitted(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase() == 'submitted';
  }

  bool _isDailyOrder(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase() == 'daily_order';
  }

  String _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _barcode(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  List<String> _barcodeList(dynamic value) {
    if (value == null) return const [];
    var rawItems = value is List ? value : <dynamic>[value];
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) rawItems = decoded;
      } catch (_) {
        rawItems = [value];
      }
    }
    final seen = <String>{};
    final out = <String>[];
    for (final raw in rawItems) {
      final barcode = _barcode(raw);
      if (barcode.isEmpty || seen.contains(barcode)) continue;
      seen.add(barcode);
      out.add(barcode);
    }
    return out;
  }
}
