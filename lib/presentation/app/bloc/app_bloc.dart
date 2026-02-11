import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/usecases/get_me.dart';
import 'app_event.dart';
import 'app_state.dart';

class AppBloc extends Bloc<AppEvent, AppState> {
  final GetMe getMe;

  AppBloc({required this.getMe}) : super(AppState.initial()) {
    on<AppStarted>(_onStarted);
  }

  Future<void> _onStarted(AppStarted event, Emitter<AppState> emit) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        emit(state.copyWith(status: AppStatus.unauthenticated, me: null));
        return;
      }

      // print('AUTH USER (AppStarted): ${user.id}');

      final me = await getMe();

      if (me == null) {
        emit(state.copyWith(status: AppStatus.unauthenticated, me: null));
      } else {
        emit(state.copyWith(status: AppStatus.authenticated, me: me));
      }
    } catch (e) {
      emit(state.copyWith(status: AppStatus.failure, error: e.toString()));
    }
  }
}
