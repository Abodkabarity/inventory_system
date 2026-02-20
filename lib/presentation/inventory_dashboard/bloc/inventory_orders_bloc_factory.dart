/*
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/datasources/remote/inventory_orders_remote_ds.dart';
import '../../../data/repositories/inventory_orders_repository_impl.dart';
import '../../../domain/usecases/generate_all_orders.dart';
import '../../../domain/usecases/get_order_job.dart';
import '../../../domain/usecases/load_headers_page.dart';
import '../../../domain/usecases/step_generate_all_orders.dart';
import 'inventory_orders_bloc.dart';

class InventoryOrdersBlocFactory {
  static InventoryOrdersBloc create() {
    final client = Supabase.instance.client;
    final remote = InventoryOrdersRemoteDs(client);
    final repo = InventoryOrdersRepositoryImpl(remote);

    return InventoryOrdersBloc(
      loadHeadersPage: LoadHeadersPage(repo),
      stepGenerateAllOrders: StepGenerateAllOrders(repo),
      getOrderJob: GetOrderJob(repo),
    );
  }
}
*/
