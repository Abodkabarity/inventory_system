import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';

/// Resolves archived galleries independently of stock/detail queries.
class StockProductImageService {
  static final _services = Expando<StockProductImageService>();
  static StockProductImageService forClient(SupabaseClient client) =>
      _services[client] ??= StockProductImageService(
        scope: () => client.auth.currentUser?.id ?? 'signed-out',
        lookup: (sku) async => Map<String, dynamic>.from(
          (await client.functions.invoke(
                'stock-product-gallery',
                body: {'sku': sku},
              )).data
              as Map,
        ),
        upload: (sku, bytes) async => Map<String, dynamic>.from(
          (await client.functions.invoke(
                'stock-product-gallery',
                body: bytes,
                headers: {
                  'Content-Type': 'application/octet-stream',
                  'x-item-code': sku,
                },
              )).data
              as Map,
        ),
      );
  final Future<Map<String, dynamic>> Function(String) lookup;
  final Future<Map<String, dynamic>> Function(String, Uint8List)? upload;
  final String Function()? scope;
  final _pending = <String, Future<List<String>>>{};
  final _cache = <String, Map<String, dynamic>>{};
  Future<void>? _ready;
  SharedPreferences? _preferences;
  String? _activeScope;
  String get _key => 'stock_product_images_v2_${_activeScope ?? 'default'}';
  StockProductImageService({required this.lookup, this.upload, this.scope});
  Future<void> _restore() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final saved = jsonDecode(_preferences!.getString(_key) ?? '{}') as Map;
      for (final entry in saved.entries.take(250)) {
        _cache[entry.key.toString()] = Map<String, dynamic>.from(entry.value);
      }
    } catch (_) {
      /* In-memory caching remains available. */
    }
  }

  void _checkScope() {
    final current = scope?.call() ?? 'default';
    if (current == _activeScope) return;
    _activeScope = current;
    _cache.clear();
    _pending.clear();
    _ready = null;
  }

  Future<String?> resolve(String sku) async {
    final images = await gallery(sku);
    return images.isEmpty ? null : images.first;
  }

  Future<List<String>> gallery(String rawSku) {
    _checkScope();
    final sku = rawSku.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(sku)) {
      return Future.value(const []);
    }
    return _pending[sku] ??= _resolve(sku).whenComplete(() {
      _pending.remove(sku);
    });
  }

  static bool validImage(String? image) {
    final uri = Uri.tryParse(image ?? '');
    if (uri == null || uri.scheme != 'https') return false;
    final storageHost = Uri.tryParse(SupabaseConfig.supabaseUrl)?.host;
    final host = (storageHost?.isNotEmpty ?? false)
        ? storageHost!
        : 'rzvxjkbraufqbfhvftcy.supabase.co';
    return (uri.host == host &&
            uri.path.startsWith(
              '/storage/v1/object/sign/stock-product-images/',
            ) &&
            uri.queryParameters.containsKey('token')) ||
        (uri.host == 'alainpharmacy-ae.gumlet.io' &&
            uri.path.startsWith('/media/catalog/product/') &&
            !uri.path.toLowerCase().contains('placeholder'));
  }

  List<String> _images(Map<String, dynamic> result) => <String>{
    for (final value in (result['images'] as List? ?? [result['image_url']]))
      if (value is String && validImage(value)) value,
  }.toList(growable: false);
  Future<void> _save(String sku, List<String> images, Duration ttl) async {
    _cache.remove(sku);
    if (_cache.length >= 250) _cache.remove(_cache.keys.first);
    _cache[sku] = {
      'images': images,
      'until': DateTime.now().add(ttl).millisecondsSinceEpoch,
    };
    try {
      await _preferences?.setString(_key, jsonEncode(_cache));
    } catch (_) {
      /* Browser storage optional. */
    }
  }

  Future<List<String>> _resolve(String sku) async {
    final requestScope = _activeScope;
    await (_ready ??= _restore());
    final saved = _cache[sku];
    if (saved != null &&
        (saved['until'] as num? ?? 0) > DateTime.now().millisecondsSinceEpoch) {
      return (saved['images'] as List? ?? [])
          .whereType<String>()
          .where(validImage)
          .toList();
    }
    try {
      final result = await lookup(sku).timeout(const Duration(seconds: 30));
      if (result['sku'] != sku) {
        throw StateError('Unexpected product image response');
      }
      final images = _images(result);
      if (_activeScope == requestScope) {
        if (result['status'] == 'found' && images.isNotEmpty) {
          final seconds = (result['expires_in'] as num? ?? 86400).toInt().clamp(
            1,
            6 * 86400,
          );
          await _save(sku, images, Duration(seconds: seconds));
        } else if (result['status'] == 'not_found') {
          await _save(sku, const [], const Duration(minutes: 1));
        }
      }
      return _activeScope == requestScope ? images : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> addImage(String sku, Uint8List bytes) async {
    _checkScope();
    await (_ready ??= _restore());
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw StateError('Choose an image under 10 MB.');
    }
    if (upload == null) throw StateError('Image upload is unavailable.');
    final result = await upload!(
      sku,
      bytes,
    ).timeout(const Duration(seconds: 60));
    final images = _images(result);
    if (result['sku'] != sku || images.isEmpty) {
      throw StateError('The image could not be saved. Please retry.');
    }
    await _save(sku, images, const Duration(days: 6));
    return images;
  }
}
