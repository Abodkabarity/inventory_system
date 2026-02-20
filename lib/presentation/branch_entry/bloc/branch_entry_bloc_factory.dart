import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/datasources/remote/supabase_branch_remote_ds.dart';
import '../../../../data/repositories/branch_repository_impl.dart';
import '../../../../domain/usecases/get_branch_name_by_id.dart';
import 'branch_entry_bloc.dart';

class BranchEntryBlocFactory {
  static BranchEntryBloc create() {
    final ds = SupabaseBranchRemoteDs(Supabase.instance.client);
    final repo = BranchRepositoryImpl(ds);
    final uc = GetBranchNameById(repo);
    return BranchEntryBloc(getBranchNameById: uc);
  }
}
