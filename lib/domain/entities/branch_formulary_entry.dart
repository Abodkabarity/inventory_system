import 'package:equatable/equatable.dart';

class BranchFormularyEntry extends Equatable {
  final String branchName;
  final String itemCode;
  final String? itemName;
  final String formularyType;

  const BranchFormularyEntry({
    required this.branchName,
    required this.itemCode,
    this.itemName,
    required this.formularyType,
  });

  @override
  List<Object?> get props => [branchName, itemCode, itemName, formularyType];
}
