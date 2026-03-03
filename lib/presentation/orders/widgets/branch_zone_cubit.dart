import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BranchZoneState {
  final String? zone;
  final bool loading;

  const BranchZoneState({required this.zone, required this.loading});

  factory BranchZoneState.initial() =>
      const BranchZoneState(zone: null, loading: true);

  BranchZoneState copyWith({String? zone, bool? loading}) {
    return BranchZoneState(
      zone: zone ?? this.zone,
      loading: loading ?? this.loading,
    );
  }
}

class BranchZoneCubit extends Cubit<BranchZoneState> {
  final SupabaseClient client;
  final String branchName;

  BranchZoneCubit({required this.client, required this.branchName})
    : super(BranchZoneState.initial()) {
    load();
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    try {
      final res = await client
          .from('branches')
          .select('zone')
          .eq('branch_name', branchName)
          .maybeSingle();

      final z = (res == null) ? '' : (res['zone'] ?? '').toString().trim();
      emit(BranchZoneState(zone: z.isEmpty ? null : z, loading: false));
    } catch (_) {
      emit(const BranchZoneState(zone: null, loading: false));
    }
  }
}
