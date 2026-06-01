import 'package:bloc/bloc.dart';

import '../../../domain/usecases/sign_in.dart';
import '../../../domain/usecases/sign_out.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final SignIn signIn;
  final SignOut signOut;

  AuthBloc({required this.signIn, required this.signOut})
    : super(AuthState.initial()) {
    on<AuthLoginSubmitted>(_onLogin);

    on<AuthTogglePasswordVisibility>((event, emit) {
      emit(state.copyWith(isObscure: !state.isObscure));
    });

    on<AuthNavConsumed>((event, emit) {
      emit(state.copyWith(navToHome: false));
    });

    on<AuthPageOpened>((event, emit) {
      emit(AuthState.initial());
    });
  }

  Future<void> _onLogin(AuthLoginSubmitted e, Emitter<AuthState> emit) async {
    emit(
      state.copyWith(
        status: AuthStatus.authenticating,
        message: 'Signing in...',
        error: null,
        clearError: true,
      ),
    );

    try {
      await signIn(e.email, e.password);

      emit(
        state.copyWith(
          status: AuthStatus.success,
          message: 'Login Successful',
          navToHome: true,
          clearError: true,
        ),
      );
    } catch (err) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          error: 'Invalid email or password',
          clearMessage: true,
        ),
      );
    }
  }
}
