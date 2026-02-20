import 'package:equatable/equatable.dart';

abstract class BranchEntryEvent extends Equatable {
  const BranchEntryEvent();
  @override
  List<Object?> get props => [];
}

class LoadMyBranchEntry extends BranchEntryEvent {
  final String branchId;
  const LoadMyBranchEntry({required this.branchId});

  @override
  List<Object?> get props => [branchId];
}
