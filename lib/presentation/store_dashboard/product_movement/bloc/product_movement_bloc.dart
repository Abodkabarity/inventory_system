import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/repositories/store_repository.dart';
import 'product_movement_event.dart';
import 'product_movement_state.dart';

class ProductMovementBloc
    extends Bloc<ProductMovementEvent, ProductMovementState> {
  final StoreRepository repo;
  Timer? _searchDebounce;

  ProductMovementBloc(this.repo) : super(ProductMovementState.initial()) {
    on<LoadProductMovementBranches>(_onLoadBranches);
    on<ProductMovementQueryChanged>(_onQueryChanged);
    on<ProductMovementSuggestionSelected>(_onSuggestionSelected);
    on<ProductMovementBranchChanged>(_onBranchChanged);
    on<ProductMovementDateRangeChanged>(_onDateRangeChanged);
    on<ProductMovementTypeChanged>(_onTypeChanged);
    on<LoadProductMovementRows>(_onLoadRows);
  }

  Future<void> _onLoadBranches(
    LoadProductMovementBranches event,
    Emitter<ProductMovementState> emit,
  ) async {
    emit(state.copyWith(loadingBranches: true, error: ''));

    try {
      final branches = await repo.fetchActiveBranchNames();
      branches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      emit(state.copyWith(loadingBranches: false, branches: branches));
    } catch (e) {
      emit(state.copyWith(loadingBranches: false, error: e.toString()));
    }
  }

  Future<void> _onQueryChanged(
    ProductMovementQueryChanged event,
    Emitter<ProductMovementState> emit,
  ) async {
    final query = event.query.trim();
    _searchDebounce?.cancel();
    emit(
      state.copyWith(
        query: event.query,
        selectedItemCode: '',
        selectedItemName: '',
        rows: const [],
        searched: false,
        loadingRows: false,
        error: '',
      ),
    );

    if (query.isEmpty) {
      emit(
        state.copyWith(
          suggestions: const [],
          rows: const [],
          searched: false,
          loadingRows: false,
        ),
      );
      return;
    }

    try {
      final suggestions = await repo.fetchMovementProductSuggestions(
        query: query,
      );
      emit(state.copyWith(suggestions: suggestions));
    } catch (_) {
      emit(state.copyWith(suggestions: const []));
    }
  }

  void _onSuggestionSelected(
    ProductMovementSuggestionSelected event,
    Emitter<ProductMovementState> emit,
  ) {
    emit(
      state.copyWith(
        query: event.itemCode,
        selectedItemCode: event.itemCode,
        selectedItemName: event.itemName,
        suggestions: const [],
        error: '',
      ),
    );
    add(LoadProductMovementRows());
  }

  void _onBranchChanged(
    ProductMovementBranchChanged event,
    Emitter<ProductMovementState> emit,
  ) {
    emit(
      state.copyWith(
        selectedBranch: event.branch,
        clearSelectedBranch: event.branch == null,
        error: '',
      ),
    );
    if (state.selectedItemCode.trim().isNotEmpty) {
      _scheduleLoad(short: true);
    }
  }

  void _onDateRangeChanged(
    ProductMovementDateRangeChanged event,
    Emitter<ProductMovementState> emit,
  ) {
    emit(state.copyWith(dateRange: event.range, error: ''));
    if (state.selectedItemCode.trim().isNotEmpty) {
      _scheduleLoad(short: true);
    }
  }

  void _onTypeChanged(
    ProductMovementTypeChanged event,
    Emitter<ProductMovementState> emit,
  ) {
    emit(state.copyWith(movementType: event.movementType, error: ''));
    if (state.selectedItemCode.trim().isNotEmpty) {
      _scheduleLoad(short: true);
    }
  }

  Future<void> _onLoadRows(
    LoadProductMovementRows event,
    Emitter<ProductMovementState> emit,
  ) async {
    final itemCode = state.selectedItemCode.trim();
    if (itemCode.isEmpty) {
      emit(state.copyWith(rows: const [], loadingRows: false, searched: false));
      return;
    }

    emit(state.copyWith(loadingRows: true, error: '', searched: true));

    try {
      final rows = await repo.fetchProductMovement(
        query: itemCode,
        branch: state.selectedBranch,
        from: state.dateRange.start,
        to: state.dateRange.end,
        movementType: state.movementType,
      );

      emit(state.copyWith(loadingRows: false, rows: rows));
    } catch (e) {
      emit(
        state.copyWith(loadingRows: false, rows: const [], error: e.toString()),
      );
    }
  }

  void _scheduleLoad({bool short = false}) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(Duration(milliseconds: short ? 80 : 380), () {
      add(LoadProductMovementRows());
    });
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    return super.close();
  }
}
