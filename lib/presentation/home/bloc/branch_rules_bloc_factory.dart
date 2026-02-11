import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/datasources/remote/sales_remote_ds.dart';
import '../../../data/repositories/sales_repository_impl.dart';
import '../../../domain/usecases/calc_30d_demand_for_branch.dart';
import 'branch_rules_bloc.dart';

class BranchRulesBlocFactory {
  static BranchRulesBloc create({SupabaseClient? client}) {
    final c = client ?? Supabase.instance.client;

    final remote = SalesRemoteDs(c);
    final repo = SalesRepositoryImpl(remote);
    final usecase = GetSalesDemand30Map(repo);

    return BranchRulesBloc(getSalesDemand30Map: usecase, client: c);
  }
}
