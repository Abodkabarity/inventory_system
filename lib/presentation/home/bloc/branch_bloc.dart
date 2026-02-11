import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'branch_event.dart';
part 'branch_state.dart';

class BranchBloc extends Bloc<BranchEvent, BranchState> {
  final SupabaseClient client;

  BranchBloc({SupabaseClient? client})
    : client = client ?? Supabase.instance.client,
      super(BranchState.initial()) {
    on<LoadMyBranch>(_onLoadMyBranch);
  }

  Future<void> _onLoadMyBranch(
    LoadMyBranch event,
    Emitter<BranchState> emit,
  ) async {
    try {
      emit(state.copyWith(status: BranchStatus.loading, error: null));

      final uid = client.auth.currentUser?.id;
      if (uid == null) {
        emit(
          state.copyWith(status: BranchStatus.failure, error: 'No logged user'),
        );
        return;
      }

      final appUser = await client
          .from('app_users')
          .select('user_id, role, branch_id')
          .eq('user_id', uid)
          .maybeSingle();

      if (appUser == null) {
        emit(
          state.copyWith(
            status: BranchStatus.failure,
            error: 'User not found in app_users',
          ),
        );
        return;
      }

      final branchId = (appUser['branch_id'] ?? '').toString();
      if (branchId.isEmpty) {
        emit(
          state.copyWith(
            status: BranchStatus.failure,
            error: 'branch_id is null in app_users',
          ),
        );
        return;
      }

      final branch = await client
          .from('branches')
          .select('id, branch_name')
          .eq('id', branchId)
          .maybeSingle();

      if (branch == null) {
        emit(
          state.copyWith(
            status: BranchStatus.failure,
            error: 'Branch not found in branches',
          ),
        );
        return;
      }

      final branchName = (branch['branch_name'] ?? '').toString().trim();
      emit(state.copyWith(status: BranchStatus.loaded, branchName: branchName));
    } catch (e) {
      emit(state.copyWith(status: BranchStatus.failure, error: e.toString()));
    }
  }
}
