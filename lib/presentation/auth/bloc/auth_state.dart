import 'package:equatable/equatable.dart';

enum AuthStatus { idle, authenticating, success, failure }

class AuthState extends Equatable {
  final AuthStatus status;
  final String? error;
  final String? message;

  final bool isObscure;
  final bool navToHome;

  const AuthState({
    this.status = AuthStatus.idle,
    this.error,
    this.message,
    this.isObscure = false,
    this.navToHome = false,
  });

  bool get isLoading => status == AuthStatus.authenticating;

  factory AuthState.initial() => const AuthState();

  AuthState copyWith({
    AuthStatus? status,
    String? error,
    String? message,
    bool? isObscure,
    bool? navToHome,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      message: clearMessage ? null : (message ?? this.message),
      isObscure: isObscure ?? this.isObscure,
      navToHome: navToHome ?? this.navToHome,
    );
  }

  @override
  List<Object?> get props => [status, error, message, isObscure, navToHome];
}
