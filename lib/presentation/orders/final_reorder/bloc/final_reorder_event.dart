import 'package:equatable/equatable.dart';

abstract class FinalReorderEvent extends Equatable {
  const FinalReorderEvent();

  @override
  List<Object?> get props => [];
}

class FinalReorderStarted extends FinalReorderEvent {
  const FinalReorderStarted();
}

class FinalReorderQtyTextChanged extends FinalReorderEvent {
  final String text;
  const FinalReorderQtyTextChanged(this.text);

  @override
  List<Object?> get props => [text];
}

class FinalReorderIncPressed extends FinalReorderEvent {
  const FinalReorderIncPressed();
}

class FinalReorderDecPressed extends FinalReorderEvent {
  const FinalReorderDecPressed();
}

class FinalReorderReasonChanged extends FinalReorderEvent {
  final String text;
  const FinalReorderReasonChanged(this.text);

  @override
  List<Object?> get props => [text];
}

class FinalReorderApplyMaxAdjChanged extends FinalReorderEvent {
  final bool value;
  const FinalReorderApplyMaxAdjChanged(this.value);

  @override
  List<Object?> get props => [value];
}

class FinalReorderResetPressed extends FinalReorderEvent {
  const FinalReorderResetPressed();
}

class FinalReorderSavePressed extends FinalReorderEvent {
  const FinalReorderSavePressed();
}

class FinalReorderDialogConsumed extends FinalReorderEvent {
  const FinalReorderDialogConsumed();
}
