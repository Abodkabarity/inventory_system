import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities.dart';
import '../domain/mobile_order_repository.dart';
import 'mobile_order_local_data_source.dart';
import 'mobile_order_remote_data_source.dart';

class MobileOrderRepositoryImpl implements MobileOrderRepository {
  final MobileOrderRemoteDataSource remote;
  final MobileOrderLocalDataSource local;

  MobileOrderRepositoryImpl(this.remote, this.local);

  @override
  Session? get currentSession => remote.currentSession;

  @override
  Future<void> ensureAllowedUser() => remote.ensureAllowedUser();

  @override
  Future<void> signIn({required String email, required String password}) {
    return remote.signIn(email: email, password: password);
  }

  @override
  Future<void> signOut() => remote.signOut();

  @override
  Future<List<BranchOption>> fetchBranchesForDate(DateTime date) async {
    await _syncPendingSubmissions();
    return _remoteThenCache(
      remoteCall: () => remote.fetchBranchesForDate(date),
      cacheSave: (rows) => local.saveBranches(date, rows),
      cacheLoad: () => local.loadBranches(date),
    );
  }

  @override
  Future<List<String>> loadPickerNames(DateTime date) {
    return local.loadPickerNames(date);
  }

  @override
  Future<void> savePickerName(DateTime date, String name) {
    return local.savePickerName(date, name);
  }

  @override
  Future<List<MobileOrderItem>> fetchBranchOrder({
    required String branch,
    required DateTime date,
  }) {
    return _remoteThenCache(
      remoteCall: () => remote.fetchBranchOrder(branch: branch, date: date),
      cacheSave: (rows) =>
          local.saveOrder(branch: branch, date: date, items: rows),
      cacheLoad: () => local.loadOrder(branch: branch, date: date),
    );
  }

  @override
  Future<Map<String, PickedItem>> loadPicked({
    required String branch,
    required DateTime date,
    required PickCategory category,
  }) {
    return local.loadPicked(branch: branch, date: date, category: category);
  }

  @override
  Future<void> savePicked({
    required String branch,
    required DateTime date,
    required PickCategory category,
    required Map<String, PickedItem> picked,
  }) {
    return local.savePicked(
      branch: branch,
      date: date,
      category: category,
      picked: picked,
    );
  }

  @override
  Future<void> submitPickedItems({
    required String branch,
    required DateTime date,
    required String pickerName,
    required PickCategory category,
    required List<MobileOrderItem> items,
    required Map<String, PickedItem> picked,
  }) {
    return _submitOrQueue(
      branch: branch,
      date: date,
      pickerName: pickerName,
      category: category,
      items: items,
      picked: picked,
    );
  }

  Future<T> _remoteThenCache<T>({
    required Future<T> Function() remoteCall,
    required Future<void> Function(T value) cacheSave,
    required Future<T> Function() cacheLoad,
  }) async {
    try {
      final value = await remoteCall();
      await cacheSave(value);
      return value;
    } on PostgrestException {
      rethrow;
    } catch (_) {
      final cached = await cacheLoad();
      if (!_hasCachedValue(cached)) rethrow;
      return cached;
    }
  }

  bool _hasCachedValue<T>(T cached) {
    if (cached is List) return cached.isNotEmpty;
    if (cached is Map) return cached.isNotEmpty;
    return cached != null;
  }

  Future<void> _submitOrQueue({
    required String branch,
    required DateTime date,
    required String pickerName,
    required PickCategory category,
    required List<MobileOrderItem> items,
    required Map<String, PickedItem> picked,
  }) async {
    final submission = {
      'branch': branch,
      'date': date.toIso8601String(),
      'pickerName': pickerName,
      'category': category.name,
      'items': items.map((e) => e.toJson()).toList(),
      'picked': picked.values.map((e) => e.toJson()).toList(),
    };

    try {
      await remote.submitPickedItems(
        branch: branch,
        date: date,
        pickerName: pickerName,
        category: category,
        items: items,
        picked: picked,
      );
    } on PostgrestException {
      rethrow;
    } catch (_) {
      await local.queueSubmission(submission);
    }
  }

  Future<void> _syncPendingSubmissions() async {
    final pending = await local.loadPendingSubmissions();
    if (pending.isEmpty) return;

    final remaining = <Map<String, dynamic>>[];
    for (final submission in pending) {
      try {
        final category = PickCategory.values.byName(
          (submission['category'] ?? PickCategory.medicine.name).toString(),
        );
        final items = List<Map<String, dynamic>>.from(
          (submission['items'] as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        ).map(MobileOrderItem.fromJson).toList();
        final pickedRows = List<Map<String, dynamic>>.from(
          (submission['picked'] as List).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        ).map(PickedItem.fromJson);
        final picked = {for (final item in pickedRows) item.itemCode: item};

        await remote.submitPickedItems(
          branch: (submission['branch'] ?? '').toString(),
          date: DateTime.parse((submission['date'] ?? '').toString()),
          pickerName: (submission['pickerName'] ?? '').toString(),
          category: category,
          items: items,
          picked: picked,
        );
      } catch (_) {
        remaining.add(submission);
      }
    }

    await local.savePendingSubmissions(remaining);
  }
}
