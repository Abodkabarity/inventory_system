import '../repositories/branch_repository.dart';

class GetBranchNameById {
  final BranchRepository repo;
  GetBranchNameById(this.repo);

  Future<String> call({required String branchId}) {
    return repo.getBranchNameById(branchId: branchId);
  }
}
