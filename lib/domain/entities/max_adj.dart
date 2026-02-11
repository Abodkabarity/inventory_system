import 'package:equatable/equatable.dart';

class MaxAdj extends Equatable {
  final String branchName;
  final String itemCode;
  final int? currentDemand30d;
  final int? maxAdjustment30d;
  final String? adjustmentType;
  final DateTime? updateDate;

  const MaxAdj({
    required this.branchName,
    required this.itemCode,
    required this.currentDemand30d,
    required this.maxAdjustment30d,
    required this.adjustmentType,
    required this.updateDate,
  });

  @override
  List<Object?> get props => [
    branchName,
    itemCode,
    currentDemand30d,
    maxAdjustment30d,
    adjustmentType,
    updateDate,
  ];
}
