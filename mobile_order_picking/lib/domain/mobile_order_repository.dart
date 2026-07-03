import 'package:supabase_flutter/supabase_flutter.dart';

import 'entities.dart';

abstract class MobileOrderRepository {
  Session? get currentSession;

  Future<void> ensureAllowedUser();

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<List<BranchOption>> fetchBranchesForDate(DateTime date);

  Future<List<String>> loadPickerNames(DateTime date);

  Future<void> savePickerName(DateTime date, String name);

  Future<List<MobileOrderItem>> fetchBranchOrder({
    required String branch,
    required DateTime date,
  });

  Future<Map<String, PickedItem>> loadPicked({
    required String branch,
    required DateTime date,
    required PickCategory category,
  });

  Future<void> savePicked({
    required String branch,
    required DateTime date,
    required PickCategory category,
    required Map<String, PickedItem> picked,
  });

  Future<void> submitPickedItems({
    required String branch,
    required DateTime date,
    required String pickerName,
    required PickCategory category,
    required List<MobileOrderItem> items,
    required Map<String, PickedItem> picked,
  });
}
