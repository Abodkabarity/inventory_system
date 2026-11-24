import '../../../core/config/stock_management_load_config.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../domain/entities/stock_catalog.dart';
import '../../../domain/entities/stock_management.dart';
import 'stock_catalog_remote_ds.dart';
import 'stock_product_image_service.dart';

/// Uses only server-derived zone scopes. No client branch/zone filter is sent.
class ZoneStockCatalogRemoteDs extends StockCatalogRemoteDs {
  ZoneStockCatalogRemoteDs(super.client)
    : super(cacheNamespace: 'zone-overview');

  String? _version;
  late final _images = StockProductImageService(
    scope: () => '${client.auth.currentUser?.id}:zone-overview',
    lookup: (code) async => stockMap(
      (await client.functions.invoke(
        'zone-stock-product-gallery',
        body: {'sku': code},
      )).data,
    ),
  );

  // A previous assignment's rows must not be previewed before server validation.
  @override
  StockCatalogResult? get previewRegister => null;
  @override
  bool get hasScopedBranchMetadata => true;
  @override
  StockProductImageService get imageService => _images;

  @override
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query) async {
    try {
      final result = StockCatalogResult.fromMap(
        stockMap(await client.rpc('get_zone_overview_header')),
      );
      final version = result.meta['catalog_cache_version']?.toString();
      if (version == null ||
          version.isEmpty ||
          result.meta['scope_kind'] != 'zone') {
        throw StateError('Invalid zone Overview response. Please retry.');
      }
      _version = version;
      return result;
    } catch (_) {
      memoryCache.clear();
      _version = null;
      rethrow;
    }
  }

  String get _requiredVersion =>
      _version ??
      (throw StateError('Load your zone Overview before opening details.'));

  @override
  Future<StockCatalogRegisterBatch> fetchRegisterBatch(int offset) async =>
      StockCatalogRegisterBatch.fromMap(
        stockMap(
          await client.rpc(
            'get_zone_overview_batch',
            params: {
              'p_offset': offset,
              'p_limit': StockManagementLoadConfig.batchSize,
              'p_version': _requiredVersion,
            },
          ),
        ),
      );

  @override
  Future<StockCatalogItem> fetchItem(String code) async {
    final version = _requiredVersion;
    final generation = memoryCache.generation;
    final result = await client.rpc(
      'get_zone_overview_item',
      params: {'p_item_code': code, 'p_version': version},
    );
    memoryCache.checkGeneration(generation);
    final data = stockMap(result);
    if (_version != version ||
        data['_cache_version'] != version ||
        data['item_code'] != code) {
      throw StateError('Product is unavailable in your zone Overview. Reload.');
    }
    final groups = <String, String>{
      ...StoreBranchIdentityRegistry.groups.value,
    };
    for (final branch in (data['branches'] as List? ?? const [])) {
      final row = stockMap(branch);
      final name = row['branch']?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        groups[name.toUpperCase()] =
            row['branch_group']?.toString().trim() ?? '';
      }
    }
    StoreBranchIdentityRegistry.groups.value = Map.unmodifiable(groups);
    return StockCatalogItem(data..remove('_cache_version'));
  }

  @override
  Future<void> requestRefresh() async =>
      throw UnsupportedError('Zone Overview is read only.');

  @override
  Future<Map<String, dynamic>?> refreshState() async => null;
}
