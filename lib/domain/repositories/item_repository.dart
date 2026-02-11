import '../entities/item.dart';

abstract class ItemRepository {
  Future<List<Item>> getCatalogItems({int limit, int offset, String? search});
}
