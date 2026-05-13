import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/datasources/remote/orders_remote_ds.dart';
import '../../../../data/repositories/orders_repository_impl.dart';
import '../../../../domain/usecases/fetch_orders_all.dart';
import 'orders_bloc.dart';
import 'orders_state.dart';

class OrdersBlocFactory {
  static OrdersBloc create({
    required String runDate,
    required String branchName,
  }) {
    final client = Supabase.instance.client;
    final remote = OrdersRemoteDs(client);
    final repo = OrdersRepositoryImpl(remote);

    return OrdersBloc(
      initialState: OrdersState.initial(
        runDate: runDate,
        branchName: branchName,
      ),
      fetchOrdersAll: FetchOrdersAll(repo),

      repo: repo,
    );
  }
}
