import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/usecases/get_stock_maps_for_branch.dart';
import 'stock_event.dart';
import 'stock_state.dart';

class StockBloc extends Bloc<StockEvent, StockState> {
  final GetStockMapsForBranch getStockMapsForBranch;

  StockBloc({required this.getStockMapsForBranch})
    : super(StockState.initial()) {
    on<LoadStockMaps>(_onLoad);
  }

  Future<void> _onLoad(LoadStockMaps e, Emitter<StockState> emit) async {
    try {
      emit(state.copyWith(status: StockStatus.loading, error: null));

      final maps = await getStockMapsForBranch(
        branchName: e.branchName.trim(),
        storeName: e.storeName.trim(),
      );

      emit(
        state.copyWith(
          status: StockStatus.loaded,
          storeStockByItemCode: maps.storeStockByItemCode,
          mismatchDiffByItemCode: maps.mismatchDiffByItemCode,
          pendingByItemCode: maps.pendingByItemCode,
          branchStockFinalByItemCode: maps.branchStockFinalByItemCode,
        ),
      );
    } catch (err) {
      emit(state.copyWith(status: StockStatus.failure, error: err.toString()));
    }
  }
}
