import 'package:equatable/equatable.dart';

class AdditionalRequest extends Equatable {
  final String id;
  final String branchName;
  final String itemCode;
  final String itemName;
  final num requestedQty;
  final num? sentQty;
  final String? note;
  final String status;

  const AdditionalRequest({
    required this.id,
    required this.branchName,
    required this.itemCode,
    required this.itemName,
    required this.requestedQty,
    required this.sentQty,
    required this.note,
    required this.status,
  });

  @override
  List<Object?> get props => [
    id,
    branchName,
    itemCode,
    itemName,
    requestedQty,
    sentQty,
    note,
    status,
  ];
}
