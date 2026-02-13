import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/usecases/load_items_page.dart';
import 'inventory_order_details_event.dart';
import 'inventory_order_details_state.dart';

class InventoryOrderDetailsBloc
    extends Bloc<InventoryOrderDetailsEvent, InventoryOrderDetailsState> {
  final LoadItemsPage loadItemsPage;

  InventoryOrderDetailsBloc({required this.loadItemsPage})
    : super(InventoryOrderDetailsState.initial()) {
    on<SetRunDate>(_onSetRunDate);
    on<LoadItems>(_onLoadItems);
  }

  Future<void> _onSetRunDate(
    SetRunDate event,
    Emitter<InventoryOrderDetailsState> emit,
  ) async {
    emit(state.copyWith(runDate: event.runDate, pageIndex: 0));
  }

  Future<void> _onLoadItems(
    LoadItems event,
    Emitter<InventoryOrderDetailsState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          status: InventoryOrderDetailsStatus.loading,
          error: null,
        ),
      );

      final rows = await loadItemsPage.call(
        branchName: event.branchName,
        runDate: state.runDate,
        pageIndex: event.pageIndex,
        pageSize: state.pageSize,
      );

      emit(
        state.copyWith(
          status: InventoryOrderDetailsStatus.ready,
          pageIndex: event.pageIndex,
          rows: rows,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: InventoryOrderDetailsStatus.failure,
          error: e.toString(),
        ),
      );
    }
  }
}
