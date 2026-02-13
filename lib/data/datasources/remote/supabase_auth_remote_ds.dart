import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_user_model.dart';

class SupabaseAuthRemoteDs {
  final SupabaseClient client;
  SupabaseAuthRemoteDs(this.client);

  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  User? currentUser() => client.auth.currentUser;

  Future<AppUserModel?> getMeFromAppUsers() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return null;

    final data = await client
        .from('app_users')
        .select('user_id, role, branch_id')
        .eq('user_id', uid)
        .maybeSingle();

    if (data == null) return null;

    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    final branchId = data['branch_id'] as String?;

    // Inventory does NOT require branch_id
    if (role == 'inventory') {
      return AppUserModel.fromMap({
        'user_id': data['user_id'],
        'role': data['role'],
        'branch_id': null,
      });
    }

    // Other roles MUST have branch_id
    if (branchId == null || branchId.isEmpty) {
      throw Exception('No branch assigned for this user in app_users.');
    }

    return AppUserModel.fromMap(data);
  }
}
