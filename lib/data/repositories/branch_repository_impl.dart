import '../../domain/entities/branch.dart';
import '../../domain/repositories/branch_repository.dart';
import '../datasources/remote/supabase_branch_remote_ds.dart';

class BranchRepositoryImpl implements BranchRepository {
  final SupabaseBranchRemoteDs ds;
  BranchRepositoryImpl(this.ds);

  @override
  Future<Branch?> getBranchById(String branchId) => ds.getBranchById(branchId);
}
