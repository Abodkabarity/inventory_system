import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/date_utils_uae.dart';
import '../domain/entities.dart';

class MobileOrderLocalDataSource {
  static const _pendingSubmissionsKey = 'pending_mobile_order_submissions';

  Future<List<BranchOption>> loadBranches(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_branchesKey(date));
    if (raw == null || raw.isEmpty) return const [];
    final data = List<dynamic>.from(jsonDecode(raw) as List);
    return data.map((e) => BranchOption(e.toString())).toList();
  }

  Future<void> saveBranches(DateTime date, List<BranchOption> branches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _branchesKey(date),
      jsonEncode(branches.map((e) => e.name).toList()),
    );
  }

  Future<List<String>> loadPickerNames(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pickerNamesKey(date));
    if (raw == null || raw.isEmpty) return const [];
    final names = List<dynamic>.from(jsonDecode(raw) as List)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<void> savePickerName(DateTime date, String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final names = List<String>.from(await loadPickerNames(date));
    final exists = names.any((e) => e.toLowerCase() == cleanName.toLowerCase());
    if (!exists) names.add(cleanName);
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await prefs.setString(_pickerNamesKey(date), jsonEncode(names));
  }

  Future<List<MobileOrderItem>> loadOrder({
    required String branch,
    required DateTime date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orderKey(branch: branch, date: date));
    if (raw == null || raw.isEmpty) return const [];
    final data = List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    return data.map(MobileOrderItem.fromJson).toList();
  }

  Future<void> saveOrder({
    required String branch,
    required DateTime date,
    required List<MobileOrderItem> items,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _orderKey(branch: branch, date: date),
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<Map<String, PickedItem>> loadPicked({
    required String branch,
    required DateTime date,
    required PickCategory category,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      _pickedKey(branch: branch, date: date, category: category),
    );
    if (raw == null || raw.isEmpty) return const {};
    final data = List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    return {
      for (final item in data.map(PickedItem.fromJson)) item.itemCode: item,
    };
  }

  Future<void> savePicked({
    required String branch,
    required DateTime date,
    required PickCategory category,
    required Map<String, PickedItem> picked,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pickedKey(branch: branch, date: date, category: category),
      jsonEncode(picked.values.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearPicked({
    required String branch,
    required DateTime date,
    required PickCategory category,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(
      _pickedKey(branch: branch, date: date, category: category),
    );
  }

  Future<void> queueSubmission(Map<String, dynamic> submission) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadPendingSubmissions();
    current.add(submission);
    await prefs.setString(_pendingSubmissionsKey, jsonEncode(current));
  }

  Future<List<Map<String, dynamic>>> loadPendingSubmissions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingSubmissionsKey);
    if (raw == null || raw.isEmpty) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  Future<void> savePendingSubmissions(List<Map<String, dynamic>> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingSubmissionsKey, jsonEncode(rows));
  }

  String _branchesKey(DateTime date) => 'branches_${ymd(date)}';

  String _pickerNamesKey(DateTime date) => 'picker_names_${ymd(date)}';

  String _orderKey({required String branch, required DateTime date}) {
    return 'order_${ymd(date)}_${_clean(branch)}';
  }

  String _pickedKey({
    required String branch,
    required DateTime date,
    required PickCategory category,
  }) {
    return 'picked_${ymd(date)}_${_clean(branch)}_${category.name}';
  }

  String _clean(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }
}
