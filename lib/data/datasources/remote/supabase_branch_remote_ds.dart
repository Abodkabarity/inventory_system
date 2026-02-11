import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/branch_model.dart';

class SupabaseBranchRemoteDs {
  final SupabaseClient client;
  SupabaseBranchRemoteDs(this.client);

  Future<BranchModel?> getBranchById(String branchId) async {
    final data = await client
        .from('branches')
        .select('id, branch_name, zone')
        .eq('id', branchId)
        .maybeSingle();

    if (data == null) return null;
    return BranchModel.fromMap(data);
  }
}
