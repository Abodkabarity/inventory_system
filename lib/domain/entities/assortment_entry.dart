import 'package:equatable/equatable.dart';

class AssortmentEntry extends Equatable {
  final String branchName;
  final String itemCode;
  final String? itemName;
  final num? assortmentQty;
  final String? assortmentBy;
  final DateTime? start;
  final DateTime? end;
  final String? reason;

  const AssortmentEntry({
    required this.branchName,
    required this.itemCode,
    this.itemName,
    this.assortmentQty,
    this.assortmentBy,
    this.start,
    this.end,
    this.reason,
  });

  @override
  List<Object?> get props => [
    branchName,
    itemCode,
    itemName,
    assortmentQty,
    assortmentBy,
    start,
    end,
    reason,
  ];
}
