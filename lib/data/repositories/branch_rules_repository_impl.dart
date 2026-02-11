import '../../domain/entities/assortment_entry.dart';
import '../../domain/entities/branch_formulary_entry.dart';
import '../../domain/entities/tma_entry.dart';
import '../../domain/repositories/branch_rules_repository.dart';
import '../datasources/remote/supabase_branch_rules_remote_ds.dart';

class BranchRulesRepositoryImpl implements BranchRulesRepository {
  final SupabaseBranchRulesRemoteDs ds;
  BranchRulesRepositoryImpl(this.ds);

  @override
  Future<List<BranchFormularyEntry>> getBranchFormulary(String branchName) =>
      ds.getBranchFormulary(branchName);

  @override
  Future<List<AssortmentEntry>> getAssortment(String branchName) =>
      ds.getAssortment(branchName);

  @override
  Future<List<TmaEntry>> getTma(String branchName) => ds.getTma(branchName);
}
