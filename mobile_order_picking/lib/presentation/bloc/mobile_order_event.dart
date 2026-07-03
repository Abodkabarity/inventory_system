part of 'mobile_order_bloc.dart';

abstract class MobileOrderEvent extends Equatable {
  const MobileOrderEvent();

  @override
  List<Object?> get props => [];
}

class AppStarted extends MobileOrderEvent {}

class LoginSubmitted extends MobileOrderEvent {
  final String email;
  final String password;

  const LoginSubmitted({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];
}

class LogoutRequested extends MobileOrderEvent {}

class BranchesRequested extends MobileOrderEvent {}

class BranchSelected extends MobileOrderEvent {
  final String branch;

  const BranchSelected(this.branch);

  @override
  List<Object?> get props => [branch];
}

class PickerNameChanged extends MobileOrderEvent {
  final String name;

  const PickerNameChanged(this.name);

  @override
  List<Object?> get props => [name];
}

class OrderRequested extends MobileOrderEvent {}

class CategorySelected extends MobileOrderEvent {
  final PickCategory category;

  const CategorySelected(this.category);

  @override
  List<Object?> get props => [category];
}

class BackToCategorySelection extends MobileOrderEvent {}

class PickConfirmed extends MobileOrderEvent {
  final MobileOrderItem item;
  final num qty;
  final String scannedBarcode;

  const PickConfirmed({
    required this.item,
    required this.qty,
    required this.scannedBarcode,
  });

  @override
  List<Object?> get props => [item, qty, scannedBarcode];
}

class CategorySubmitted extends MobileOrderEvent {}

class MessageCleared extends MobileOrderEvent {}
