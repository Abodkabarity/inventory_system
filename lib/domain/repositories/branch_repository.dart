abstract class BranchRepository {
  Future<String> getMyBranchName();

  Future<String> getBranchNameById({required String branchId});

  // Keep this for backward compatibility, but make it abstract
  Future<String> getBranchById({required String branchId});
}
