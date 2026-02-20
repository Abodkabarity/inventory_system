import '../../domain/repositories/branch_repository.dart';
import '../datasources/remote/supabase_branch_remote_ds.dart';

class BranchRepositoryImpl implements BranchRepository {
  final SupabaseBranchRemoteDs remote;

  BranchRepositoryImpl(this.remote);

  @override
  Future<String> getMyBranchName() {
    // Keep your existing implementation here if you already use it elsewhere.
    throw UnimplementedError();
  }

  @override
  Future<String> getBranchNameById({required String branchId}) {
    return remote.getBranchNameById(branchId: branchId);
  }

  @override
  Future<String> getBranchById({required String branchId}) {
    // Alias to the new method
    return getBranchNameById(branchId: branchId);
  }
}
