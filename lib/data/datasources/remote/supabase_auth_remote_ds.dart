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
        .select('user_id, role, branch_id, is_active')
        .eq('user_id', uid)
        .maybeSingle();

    print('getMeFromAppUsers uid=$uid data=$data');

    if (data == null) {
      throw Exception(
        'No app_users row found for this uid (or blocked by RLS).',
      );
    }

    final branchId = data['branch_id'] as String?;
    if (branchId == null || branchId.isEmpty) {
      throw Exception('No branch assigned for this user in app_users.');
    }

    return AppUserModel.fromMap(data);
  }
}
