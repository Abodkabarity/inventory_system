import '../entities/assortment_entry.dart';
import '../entities/branch_formulary_entry.dart';
import '../entities/tma_entry.dart';

abstract class BranchRulesRepository {
  Future<List<BranchFormularyEntry>> getBranchFormulary(String branchName);
  Future<List<AssortmentEntry>> getAssortment(String branchName);
  Future<List<TmaEntry>> getTma(String branchName);
}
