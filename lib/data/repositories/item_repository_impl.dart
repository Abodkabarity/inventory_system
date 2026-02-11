import '../../domain/entities/item.dart';
import '../../domain/repositories/item_repository.dart';
import '../datasources/remote/supabase_item_remote_ds.dart';

class ItemRepositoryImpl implements ItemRepository {
  final SupabaseItemRemoteDs ds;
  ItemRepositoryImpl(this.ds);

  @override
  Future<List<Item>> getCatalogItems({
    int limit = 50,
    int offset = 0,
    String? search,
  }) {
    return ds.getCatalogItems(limit: limit, offset: offset, search: search);
  }
}
