import '../entities/branch_rules_bundle.dart';
import '../repositories/branch_rules_repo.dart';

class GetBranchRules {
  final BranchRulesRepo repo;
  GetBranchRules(this.repo);

  Future<BranchRulesBundle> call(String branchName) {
    return repo.getBranchRules(branchName);
  }
}
