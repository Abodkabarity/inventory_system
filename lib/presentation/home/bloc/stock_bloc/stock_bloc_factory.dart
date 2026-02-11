import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/datasources/remote/stock_remote_ds.dart';
import '../../../../data/repositories/stock_repository_impl.dart';
import '../../../../domain/usecases/get_stock_maps_for_branch.dart';
import 'stock_bloc.dart';

class StockBlocFactory {
  static StockBloc create({SupabaseClient? client}) {
    final c = client ?? Supabase.instance.client;

    final remote = StockRemoteDs(c);
    final repo = StockRepositoryImpl(remote);
    final usecase = GetStockMapsForBranch(repo);

    return StockBloc(getStockMapsForBranch: usecase);
  }
}
