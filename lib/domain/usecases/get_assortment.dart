import '../entities/assortment_entry.dart';
import '../repositories/branch_rules_repository.dart';

class GetAssortment {
  final BranchRulesRepository repo;
  GetAssortment(this.repo);

  Future<List<AssortmentEntry>> call(String branchName) =>
      repo.getAssortment(branchName);
}
