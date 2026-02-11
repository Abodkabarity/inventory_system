import 'package:bloc/bloc.dart';

import '../../../domain/usecases/sign_in.dart';
import '../../../domain/usecases/sign_out.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final SignIn signIn;
  final SignOut signOut;

  AuthBloc({required this.signIn, required this.signOut})
    : super(AuthState.idle()) {
    on<AuthLoginSubmitted>(_onLogin);
  }

  Future<void> _onLogin(AuthLoginSubmitted e, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.loading, error: null));
    try {
      await signIn(e.email, e.password);
      emit(state.copyWith(status: AuthStatus.success));
    } catch (err) {
      emit(state.copyWith(status: AuthStatus.failure, error: err.toString()));
    }
  }
}
