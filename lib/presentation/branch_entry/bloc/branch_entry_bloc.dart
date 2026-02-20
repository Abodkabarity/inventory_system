import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/usecases/get_branch_name_by_id.dart';
import 'branch_entry_event.dart';
import 'branch_entry_state.dart';

class BranchEntryBloc extends Bloc<BranchEntryEvent, BranchEntryState> {
  final GetBranchNameById getBranchNameById;

  BranchEntryBloc({required this.getBranchNameById})
    : super(BranchEntryState.initial()) {
    on<LoadMyBranchEntry>(_onLoad);
  }

  Future<void> _onLoad(
    LoadMyBranchEntry event,
    Emitter<BranchEntryState> emit,
  ) async {
    emit(state.copyWith(status: BranchEntryStatus.loading, error: null));

    try {
      final name = await getBranchNameById(branchId: event.branchId);
      emit(state.copyWith(status: BranchEntryStatus.success, branchName: name));
    } catch (e) {
      emit(
        state.copyWith(status: BranchEntryStatus.failure, error: e.toString()),
      );
    }
  }
}
