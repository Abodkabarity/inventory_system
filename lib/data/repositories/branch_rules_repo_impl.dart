import '../../domain/entities/branch_rules_bundle.dart';
import '../../domain/repositories/branch_rules_repo.dart';
import '../datasources/remote/branch_rules_remote_ds.dart';

class BranchRulesRepoImpl implements BranchRulesRepo {
  final BranchRulesRemoteDs remote;
  BranchRulesRepoImpl(this.remote);

  @override
  Future<BranchRulesBundle> getBranchRules(String branchName) async {
    final formulary = await remote.getFormulary(branchName);
    final assortment = await remote.getAssortment(branchName);
    final tma = await remote.getTma(branchName);
    final maxAdj = await remote.getMaxAdj(branchName);

    return BranchRulesBundle(
      formulary: formulary,
      assortment: assortment,
      tma: tma,
      maxAdj: maxAdj,
    );
  }
}
