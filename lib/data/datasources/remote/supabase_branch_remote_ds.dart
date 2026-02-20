import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBranchRemoteDs {
  final SupabaseClient client;
  SupabaseBranchRemoteDs(this.client);

  Future<String> getBranchNameById({required String branchId}) async {
    final res = await client
        .from('branches')
        .select('branch_name')
        .eq('id', branchId)
        .maybeSingle();

    if (res == null) {
      throw Exception('Branch not found for id=$branchId');
    }

    final name = (res['branch_name'] ?? '').toString().trim();
    if (name.isEmpty) {
      throw Exception('branch_name is empty for id=$branchId');
    }
    return name;
  }
}
