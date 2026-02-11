import '../entities/tma_entry.dart';
import '../repositories/branch_rules_repository.dart';

class GetTma {
  final BranchRulesRepository repo;
  GetTma(this.repo);

  Future<List<TmaEntry>> call(String branchName) => repo.getTma(branchName);
}
