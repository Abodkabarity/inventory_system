import '../entities/branch_formulary_entry.dart';
import '../repositories/branch_rules_repository.dart';

class GetBranchFormulary {
  final BranchRulesRepository repo;
  GetBranchFormulary(this.repo);

  Future<List<BranchFormularyEntry>> call(String branchName) =>
      repo.getBranchFormulary(branchName);
}
