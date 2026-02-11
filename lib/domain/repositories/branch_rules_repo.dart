import '../entities/branch_rules_bundle.dart';

abstract class BranchRulesRepo {
  Future<BranchRulesBundle> getBranchRules(String branchName);
}
