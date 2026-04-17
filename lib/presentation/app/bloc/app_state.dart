import 'package:equatable/equatable.dart';

import '../../../domain/entities/app_user.dart';

enum AppStatus { initial, loading, authenticated, unauthenticated, failure }

class AppState extends Equatable {
  final AppStatus status;
  final AppUser? me;
  final String? error;
  final String? runDate;
  const AppState({required this.status, this.me, this.error, this.runDate});

  factory AppState.initial() => const AppState(status: AppStatus.initial);

  AppState copyWith({
    AppStatus? status,
    AppUser? me,
    String? error,
    bool clearUser = false,
    String? runDate,
  }) {
    return AppState(
      status: status ?? this.status,
      me: clearUser ? null : (me ?? this.me),
      error: error,
      runDate: runDate ?? this.runDate,
    );
  }

  @override
  List<Object?> get props => [status, me, error];
}
