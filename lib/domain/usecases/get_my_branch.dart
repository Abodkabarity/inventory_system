import '../entities/branch.dart';
import '../repositories/branch_repository.dart';

class GetMyBranch {
  final BranchRepository repo;
  GetMyBranch(this.repo);

  Future<Branch?> call(String branchId) => repo.getBranchById(branchId);
}
