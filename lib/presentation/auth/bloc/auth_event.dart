import 'package:equatable/equatable.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthLoginSubmitted extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginSubmitted(this.email, this.password);

  @override
  List<Object?> get props => [email, password];
}

class AuthTogglePasswordVisibility extends AuthEvent {}

class AuthNavConsumed extends AuthEvent {}

class AuthPageOpened extends AuthEvent {}
