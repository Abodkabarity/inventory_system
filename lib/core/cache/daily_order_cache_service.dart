import 'dart:convert';

import 'package:hive/hive.dart';

import '../../domain/entities/daily_order_row.dart';

class DailyOrderCacheService {
  DailyOrderCacheService._();

  static final DailyOrderCacheService instance = DailyOrderCacheService._();

  static const String _boxName = 'daily_order_cache_v1';
  static const int _expireHour = 8;

  Box<dynamic>? _box;

  Future<Box<dynamic>> get _openBox async {
    _box ??= await Hive.openBox<dynamic>(_boxName);
    return _box!;
  }

  Future<void> clearExpired() async {
    final box = await _openBox;
    final now = DateTime.now();
    final metaKeys = box.keys
        .whereType<String>()
        .where((key) => key.startsWith('meta:'))
        .toList();

    for (final metaKey in metaKeys) {
      final meta = Map<String, dynamic>.from(box.get(metaKey) as Map);
      final runDate = (meta['runDate'] ?? '').toString();
      final expiresAt = DateTime.tryParse((meta['expiresAt'] ?? '').toString());
      final complete = meta['complete'] == true;

      if (!complete || expiresAt == null || !now.isBefore(expiresAt)) {
        await delete(runDate);
      }
    }
  }

  Future<List<DailyOrderRow>?> readRows(String runDate) async {
    await clearExpired();

    final box = await _openBox;
    final meta = _readMeta(box, runDate);
    if (meta == null) return null;

    final expiresAt = DateTime.tryParse((meta['expiresAt'] ?? '').toString());
    final complete = meta['complete'] == true;
    final batchCount = (meta['batchCount'] as num?)?.toInt() ?? 0;

    if (!complete || batchCount <= 0 || expiresAt == null) return null;
    if (!DateTime.now().isBefore(expiresAt)) {
      await delete(runDate);
      return null;
    }

    final rows = <DailyOrderRow>[];
    for (var i = 0; i < batchCount; i++) {
      final encoded = box.get(_batchKey(runDate, i));
      if (encoded is! String || encoded.isEmpty) return null;

      final decoded = jsonDecode(encoded) as List<dynamic>;
      rows.addAll(
        decoded.map((e) => DailyOrderRow.fromMap(Map<String, dynamic>.from(e))),
      );
    }

    return rows;
  }

  Future<void> startWrite(String runDate) async {
    await delete(runDate);
    final box = await _openBox;

    await box.put(_metaKey(runDate), {
      'runDate': runDate,
      'savedAt': DateTime.now().toIso8601String(),
      'expiresAt': _nextEightAm().toIso8601String(),
      'batchCount': 0,
      'totalRows': 0,
      'complete': false,
    });
  }

  Future<void> appendBatch(
    String runDate,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;

    final box = await _openBox;
    final meta = _readMeta(box, runDate);
    if (meta == null) return;

    final batchIndex = (meta['batchCount'] as num?)?.toInt() ?? 0;
    final totalRows = (meta['totalRows'] as num?)?.toInt() ?? 0;

    await box.put(_batchKey(runDate, batchIndex), jsonEncode(rows));
    await box.put(_metaKey(runDate), {
      ...meta,
      'batchCount': batchIndex + 1,
      'totalRows': totalRows + rows.length,
      'savedAt': DateTime.now().toIso8601String(),
      'expiresAt': _nextEightAm().toIso8601String(),
    });
  }

  Future<void> markComplete(String runDate) async {
    final box = await _openBox;
    final meta = _readMeta(box, runDate);
    if (meta == null) return;

    await box.put(_metaKey(runDate), {
      ...meta,
      'complete': true,
      'savedAt': DateTime.now().toIso8601String(),
      'expiresAt': _nextEightAm().toIso8601String(),
    });
  }

  Future<void> delete(String runDate) async {
    if (runDate.isEmpty) return;

    final box = await _openBox;
    final meta = _readMeta(box, runDate);
    final batchCount = (meta?['batchCount'] as num?)?.toInt() ?? 0;

    await box.delete(_metaKey(runDate));
    for (var i = 0; i < batchCount; i++) {
      await box.delete(_batchKey(runDate, i));
    }
  }

  Map<String, dynamic>? _readMeta(Box<dynamic> box, String runDate) {
    final raw = box.get(_metaKey(runDate));
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  String _metaKey(String runDate) => 'meta:$runDate';

  String _batchKey(String runDate, int batchIndex) {
    return 'rows:$runDate:$batchIndex';
  }

  DateTime _nextEightAm() {
    final now = DateTime.now();
    final todayEight = DateTime(now.year, now.month, now.day, _expireHour);
    if (now.isBefore(todayEight)) return todayEight;
    return todayEight.add(const Duration(days: 1));
  }
}
