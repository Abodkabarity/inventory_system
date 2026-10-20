import '../../../domain/entities/stock_catalog.dart';

/// Session-memory only. Every reuse requires a fresh server revision check.
class StockCatalogMemoryCache {
  final int maxDetails;
  final _details = <String, (String, StockCatalogItem)>{};
  final _pending = <String, Future<StockCatalogItem>>{};
  StockCatalogResult? _register;
  int _generation = 0;

  StockCatalogMemoryCache({this.maxDetails = 24}) : assert(maxDetails > 0);

  int get generation => _generation;

  void clear() {
    _generation++;
    _register = null;
    _details.clear();
    _pending.clear();
  }

  void checkGeneration(int generation) {
    if (generation != _generation) {
      throw StateError('Stock data or account changed. Please retry.');
    }
  }

  StockCatalogResult? reuseRegister(StockCatalogResult overview) {
    final version = overview.meta['catalog_cache_version'];
    final saved = _register;
    if (version == null ||
        version == '' ||
        saved == null ||
        saved.meta['catalog_cache_version'] != version ||
        saved.rows.length != overview.total) {
      _register = null;
      return null;
    }
    return StockCatalogResult(
      rows: saved.rows,
      summary: overview.summary,
      meta: overview.meta,
      categories: overview.categories,
      suppliers: overview.suppliers,
    );
  }

  void rememberRegister(StockCatalogResult result, int generation) {
    checkGeneration(generation);
    final version = result.meta['catalog_cache_version'];
    if (version != null &&
        version != '' &&
        result.rows.length == result.total) {
      _register = result;
    }
  }

  Future<StockCatalogItem> item(
    String code,
    Future<Map<String, dynamic>?> Function(String? knownVersion) load,
  ) {
    final pending = _pending[code];
    if (pending != null) return pending;
    final generation = _generation;
    final saved = _details.remove(code);
    late final Future<StockCatalogItem> request;
    request = () async {
      try {
        final response = await load(saved?.$1);
        checkGeneration(generation);
        if (response == null) {
          throw StateError('Product no longer available. Reload Overview.');
        }
        final version = response['_cache_version']?.toString();
        final StockCatalogItem result;
        if (response['_cache_not_modified'] == true) {
          if (saved == null || version == null || saved.$1 != version) {
            throw StateError('Invalid stock cache response. Please retry.');
          }
          result = saved.$2;
        } else {
          result = StockCatalogItem(
            Map<String, dynamic>.unmodifiable(
              {...response}
                ..remove('_cache_version')
                ..remove('_cache_not_modified'),
            ),
          );
          if (result.code != code) {
            throw StateError(
              'Unexpected product in stock response. Please retry.',
            );
          }
        }
        if (version != null && version.isNotEmpty) {
          _details[code] = (version, result);
          while (_details.length > maxDetails) {
            _details.remove(_details.keys.first);
          }
        }
        return result;
      } finally {
        if (identical(_pending[code], request)) _pending.remove(code);
      }
    }();
    _pending[code] = request;
    return request;
  }
}
