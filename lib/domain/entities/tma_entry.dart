import 'package:equatable/equatable.dart';

class TmaEntry extends Equatable {
  final String branchName;
  final String itemCode;
  final String? itemName;
  final DateTime? start;
  final DateTime? end;
  final num? finalQtyToKeep;
  final num? qtyPerDuration;

  const TmaEntry({
    required this.branchName,
    required this.itemCode,
    this.itemName,
    this.start,
    this.end,
    this.finalQtyToKeep,
    this.qtyPerDuration,
  });

  @override
  List<Object?> get props => [
    branchName,
    itemCode,
    itemName,
    start,
    end,
    finalQtyToKeep,
    qtyPerDuration,
  ];
}
