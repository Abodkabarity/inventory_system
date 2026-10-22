import 'package:equatable/equatable.dart';

class MismatchItem extends Equatable {
  final String branchName;
  final String itemCode;
  final String itemName;
  final num systemStock;
  final num actualStock;
  final num diff;
  final DateTime updateDate;

  final bool hasHistory;

  const MismatchItem({
    required this.branchName,
    required this.itemCode,
    required this.itemName,
    required this.systemStock,
    required this.actualStock,
    required this.diff,
    required this.updateDate,
    required this.hasHistory,
  });

  @override
  List<Object?> get props => [
    branchName,
    itemCode,
    itemName,
    systemStock,
    actualStock,
    diff,
    updateDate,
    hasHistory,
  ];
}
