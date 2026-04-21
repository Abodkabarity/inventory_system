import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/usecases/get_me.dart';
import 'app_event.dart';
import 'app_state.dart';

class AppBloc extends Bloc<AppEvent, AppState> {
  final GetMe getMe;

  late final StreamSubscription _authSub;

  AppBloc({required this.getMe}) : super(AppState.initial()) {
    on<AppStarted>(_onStarted);
    on<AppLoggedOut>(_onLoggedOut);

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.initialSession) return;

      if (session != null) {
        add(const AppStarted());
      } else {
        add(const AppLoggedOut());
      }
    });

    add(const AppStarted());
  }

  // ==========================
  // 🔥 BUSINESS DATE (9 PM)
  // ==========================
  String _getBusinessDate() {
    final now = DateTime.now().toLocal();

    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
      21, // 9 PM
    );

    final businessDate = now.isAfter(cutoff)
        ? now.add(const Duration(days: 1))
        : now;

    return businessDate.toIso8601String().split('T').first;
  }

  // ==========================
  // START
  // ==========================
  Future<void> _onStarted(AppStarted event, Emitter<AppState> emit) async {
    try {
      emit(state.copyWith(status: AppStatus.loading));

      final session = Supabase.instance.client.auth.currentSession;

      if (session == null) {
        emit(
          state.copyWith(
            status: AppStatus.unauthenticated,
            me: null,
            runDate: null,
          ),
        );
        return;
      }

      final me = await getMe();

      if (me == null) {
        emit(
          state.copyWith(
            status: AppStatus.unauthenticated,
            me: null,
            runDate: null,
          ),
        );
        return;
      }

      final runDate = _getBusinessDate();

      emit(
        state.copyWith(
          status: AppStatus.authenticated,
          me: me,
          runDate: runDate,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: AppStatus.failure, error: e.toString()));
    }
  }

  // ==========================
  // LOGOUT
  // ==========================
  void _onLoggedOut(AppLoggedOut event, Emitter<AppState> emit) {
    emit(
      state.copyWith(
        status: AppStatus.unauthenticated,
        me: null,
        runDate: null,
      ),
    );
  }

  // ==========================
  // DISPOSE
  // ==========================
  @override
  Future<void> close() {
    _authSub.cancel();
    return super.close();
  }
}
