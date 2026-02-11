import 'package:equatable/equatable.dart';

enum AuthStatus { idle, loading, success, failure }

class AuthState extends Equatable {
  final AuthStatus status;
  final String? error;

  const AuthState({required this.status, this.error});
  factory AuthState.idle() => const AuthState(status: AuthStatus.idle);

  AuthState copyWith({AuthStatus? status, String? error}) {
    return AuthState(status: status ?? this.status, error: error);
  }

  @override
  List<Object?> get props => [status, error];
}
