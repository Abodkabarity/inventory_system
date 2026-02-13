import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../data/datasources/remote/inventory_orders_remote_ds.dart';
import '../../../../data/repositories/inventory_orders_repository_impl.dart';
import '../../../../domain/usecases/load_items_page.dart';
import 'inventory_order_details_bloc.dart';

class InventoryOrderDetailsBlocFactory {
  static InventoryOrderDetailsBloc create() {
    final client = Supabase.instance.client;
    final remote = InventoryOrdersRemoteDs(client);
    final repo = InventoryOrdersRepositoryImpl(remote);

    return InventoryOrderDetailsBloc(loadItemsPage: LoadItemsPage(repo));
  }
}
