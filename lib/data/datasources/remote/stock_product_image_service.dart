import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Optional, on-demand enrichment; never part of a register or details query.
class StockProductImageService {
  static final _services = Expando<StockProductImageService>();
  static StockProductImageService forClient(SupabaseClient client) =>
      _services[client] ??= StockProductImageService(
        lookup: (sku) async {
          final response = await client.functions.invoke(
            'stock-product-image',
            body: {'sku': sku},
          );
          return Map<String, dynamic>.from(response.data as Map);
        },
      );

  final Future<Map<String, dynamic>> Function(String) lookup;
  final _pending = <String, Future<String?>>{};
  final _cache = <String, Map<String, dynamic>>{};
  Future<void>? _ready;
  SharedPreferences? _preferences;
  static const _key = 'stock_product_images_v1';
  StockProductImageService({required this.lookup});

  Future<void> _restore() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final saved = jsonDecode(_preferences!.getString(_key) ?? '{}') as Map;
      for (final entry in saved.entries.take(250)) {
        _cache[entry.key.toString()] = Map<String, dynamic>.from(entry.value);
      }
    } catch (_) {
      // Local storage may be unavailable; in-memory caching still works.
    }
  }

  Future<String?> resolve(String rawSku) {
    final sku = rawSku.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(sku)) {
      return Future.value(null);
    }
    return _pending[sku] ??= _resolve(sku).whenComplete(() {
      _pending.remove(sku);
    });
  }

  static bool validImage(String? image) {
    final uri = Uri.tryParse(image ?? '');
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'alainpharmacy-ae.gumlet.io' &&
        uri.path.startsWith('/media/catalog/product/') &&
        !uri.path.toLowerCase().contains('placeholder');
  }

  Future<String?> _resolve(String sku) async {
    await (_ready ??= _restore());
    final now = DateTime.now().millisecondsSinceEpoch;
    final saved = _cache[sku];
    if (saved != null && (saved['until'] as num? ?? 0) > now) {
      final image = saved['image'] as String?;
      return validImage(image) ? image : null;
    }
    String? image;
    Duration ttl = const Duration(minutes: 1);
    bool persist = false;
    try {
      final result = await lookup(sku).timeout(const Duration(seconds: 12));
      if (result['sku'] == sku) {
        final candidate = result['image_url'] as String?;
        if (result['status'] == 'found' && validImage(candidate)) {
          image = candidate;
          ttl = const Duration(days: 1);
          persist = true;
        } else if (result['status'] == 'not_found') {
          ttl = const Duration(hours: 6);
          persist = true;
        }
      }
    } catch (_) {
      // Short backoff for transient errors; never cache them as a missing product.
    }
    _cache.remove(sku);
    if (_cache.length >= 250) _cache.remove(_cache.keys.first);
    _cache[sku] = {
      'image': image,
      'until': DateTime.now().add(ttl).millisecondsSinceEpoch,
    };
    if (persist) {
      // Return the image without waiting for browser/disk persistence.
      _persist();
    }
    return image;
  }

  Future<void> _persist() async {
    try {
      await _preferences?.setString(_key, jsonEncode(_cache));
    } catch (_) {
      // A full or disabled local store must not interrupt the dialog.
    }
  }
}
