import '../entities/item.dart';
import '../repositories/item_repository.dart';

class GetCatalogItemsForBranch {
  final ItemRepository repo;
  GetCatalogItemsForBranch(this.repo);

  Future<List<Item>> call({int limit = 50, int offset = 0, String? search}) {
    return repo.getCatalogItems(limit: limit, offset: offset, search: search);
  }
}
