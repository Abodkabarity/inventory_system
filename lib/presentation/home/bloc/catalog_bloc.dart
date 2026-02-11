import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalog_event.dart';
import 'catalog_state.dart';

class CatalogBloc extends Bloc<CatalogEvent, CatalogState> {
  CatalogBloc() : super(CatalogState.initial()) {
    on<LoadItemReport>(_onLoadItemReport);
    on<SearchChanged>(_onSearchChanged);
    on<UpdateRowField>(_onUpdateRowField);
  }

  static const int _pageSize = 500;

  Future<void> _onLoadItemReport(
    LoadItemReport event,
    Emitter<CatalogState> emit,
  ) async {
    if (state.isLoading) return;

    emit(
      state.copyWith(
        isLoading: true,
        progress: 0,
        loaded: 0,
        total: 0,
        allRows: [],
        viewRows: [],
        error: null,
      ),
    );

    try {
      final client = Supabase.instance.client;

      // ✅ عدّ إجمالي الصفوف (طريقة متوافقة مع نسخ supabase القديمة)
      final countList = await client.from('item_report').select('item_code');
      final total = (countList as List).length;

      if (total == 0) {
        emit(
          state.copyWith(
            isLoading: false,
            progress: 1,
            loaded: 0,
            total: 0,
            allRows: const [],
            viewRows: const [],
          ),
        );
        return;
      }

      final List<Map<String, dynamic>> buffer = [];
      int from = 0;

      while (from < total) {
        final int to = (from + _pageSize - 1).clamp(0, total - 1);

        final data = await client
            .from('item_report')
            .select(
              'item_code,item_name,category,sub_category,company,supplier,'
              'indication,main_ingredient,pack_size_volume,concentration,product_type,'
              'retail,tax_percent,is_upp,insurance_tier,min_order_unit,'
              'barcode,store_classification,item_status,item_priority',
            )
            .range(from, to);

        for (final obj in (data as List)) {
          // ✅ مهم للويب: نحول أي LegacyJavaScriptObject إلى Dart primitives
          final clean = _normalizeMap(obj as Map);
          buffer.add(_mapItemReportToRow(clean));
        }

        from += _pageSize;

        final loaded = buffer.length;
        final progress = (loaded / total).clamp(0.0, 1.0);

        final view = _applySearchToRows(buffer, state.search);

        emit(
          state.copyWith(
            isLoading: true,
            total: total,
            loaded: loaded,
            progress: progress,
            allRows: List<Map<String, dynamic>>.from(buffer),
            viewRows: List<Map<String, dynamic>>.from(view),
          ),
        );
      }

      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onSearchChanged(SearchChanged event, Emitter<CatalogState> emit) {
    final q = event.query.trim();
    final view = _applySearchToRows(state.allRows, q);

    emit(
      state.copyWith(
        search: q,
        viewRows: List<Map<String, dynamic>>.from(view),
      ),
    );
  }

  void _onUpdateRowField(UpdateRowField event, Emitter<CatalogState> emit) {
    if (event.index < 0 || event.index >= state.viewRows.length) return;

    // نعدّل داخل viewRows ثم ننعكس على allRows عبر item_code (أضمن من index)
    final viewRows = List<Map<String, dynamic>>.from(state.viewRows);
    final row = Map<String, dynamic>.from(viewRows[event.index]);
    row[event.field] = event.value;
    viewRows[event.index] = row;

    final code = (row['item_code'] ?? '').toString();

    final allRows = state.allRows.map((r) {
      if ((r['item_code'] ?? '').toString() == code) {
        final updated = Map<String, dynamic>.from(r);
        updated[event.field] = event.value;
        return updated;
      }
      return r;
    }).toList();

    emit(state.copyWith(allRows: allRows, viewRows: viewRows));
  }

  // =================== Helpers ===================

  List<Map<String, dynamic>> _applySearchToRows(
    List<Map<String, dynamic>> rows,
    String query,
  ) {
    if (query.isEmpty) return rows;

    final s = query.toLowerCase();
    return rows.where((r) {
      final code = (r['item_code'] ?? '').toString().toLowerCase();
      final name = (r['item_name'] ?? '').toString().toLowerCase();
      final barcode = (r['barcode'] ?? '').toString().toLowerCase();
      final branch = (r['branch'] ?? '').toString().toLowerCase();
      return code.contains(s) ||
          name.contains(s) ||
          barcode.contains(s) ||
          branch.contains(s);
    }).toList();
  }

  Map<String, dynamic> _mapItemReportToRow(Map<String, dynamic> r) {
    return {
      // From item_report
      'item_code': r['item_code'],
      'item_name': r['item_name'],
      'category': r['category'],
      'sub_category': r['sub_category'],
      'company': r['company'],
      'supplier': r['supplier'],
      'indication': r['indication'],
      'main_ingredient': r['main_ingredient'],
      'pack_size_volume': r['pack_size_volume'],
      'concentration': r['concentration'],

      // ✅ نفس اسم الحقل الذي كنت تستخدمه
      'product_type_form': r['product_type'],

      // ✅ تركته كما هو عندك (حتى لو كان اسم العمود retail)
      'retail': r['retail'],

      // ✅ tax_percent من الريكورد
      'tax_percent': r['tax_percent'],

      // ✅ موجود عندك بالـ row حتى لو غير جاي من select (سيكون null وهذا OK)
      'vat': r['vat'],

      'is_upp': r['is_upp'],
      'insurance_tier': r['insurance_tier'],
      'min_order_unit': r['min_order_unit'],
      'barcode': r['barcode'],
      'store_classification': r['store_classification'],
      'item_status': r['item_status'],
      'item_priority': r['item_priority'],

      // Not from item_report yet
      'branch': '',
      'goods_received_last_7_days': '',
      'branch_stock': '',
      'mismatch_stock': '',
      'store_stock': '',
      'pending_stock_received': '',
      'extra_qty_more_than_month': '',
      'max_adjustment_30d': '',
      'demand_for_30_days': '',
      'reorder_point_min': '',
      'reorder_max': '',
      'reorder_qty': '',
      'final_reorder_qty_store_stock_gt_0': '',
      'date_of_last_qty_received_in_branch': '',
      'total_sold_qty_cash_last_90': '',
      'total_sold_qty_online_last_90': '',
      'total_sold_qty_insurance_last_90': '',
      'qty_30_days_from_last_45d': '',
      'branch_formulary': '',
      'assortment_qty_base_stock': '',
      'assortment_by': '',
      'reason': '',
      'assortment_start': '',
      'assortment_end': '',
      'tma_qty': '',
      'tma_start': '',
      'tma_end': '',

      // editable fields
      'final_qty': '',
    };
  }

  // ✅ تنظيف بيانات Supabase للويب (LegacyJavaScriptObject -> Dart types)
  Map<String, dynamic> _normalizeMap(Map m) {
    return m.map((key, value) => MapEntry(key.toString(), _toDart(value)));
  }

  dynamic _toDart(dynamic v) {
    if (v == null) return null;
    if (v is String || v is num || v is bool) return v;

    if (v is DateTime) return v.toIso8601String();

    if (v is List) {
      return v.map(_toDart).toList();
    }

    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _toDart(val)));
    }

    return v.toString();
  }
}
