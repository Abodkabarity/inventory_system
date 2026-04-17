import 'package:equatable/equatable.dart';

sealed class AppEvent extends Equatable {
  const AppEvent();
  @override
  List<Object?> get props => [];
}

class AppStarted extends AppEvent {
  const AppStarted();
}

class AppLoggedOut extends AppEvent {
  const AppLoggedOut();
}
