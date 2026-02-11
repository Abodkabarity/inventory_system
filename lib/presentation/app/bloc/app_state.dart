import 'package:equatable/equatable.dart';

import '../../../domain/entities/app_user.dart';

enum AppStatus { initial, authenticated, unauthenticated, failure }

class AppState extends Equatable {
  final AppStatus status;
  final AppUser? me;
  final String? error;

  const AppState({required this.status, this.me, this.error});

  factory AppState.initial() => const AppState(status: AppStatus.initial);

  AppState copyWith({AppStatus? status, AppUser? me, String? error}) {
    return AppState(
      status: status ?? this.status,
      me: me ?? this.me,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, me, error];
}
