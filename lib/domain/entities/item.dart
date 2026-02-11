import 'package:equatable/equatable.dart';

class Item extends Equatable {
  final String itemCode;
  final String itemName;
  final String? barcode;
  final String? status;
  final bool isBlock;
  final String? itemStatus;

  const Item({
    required this.itemCode,
    required this.itemName,
    this.barcode,
    this.status,
    required this.isBlock,
    this.itemStatus,
  });

  @override
  List<Object?> get props => [
    itemCode,
    itemName,
    barcode,
    status,
    isBlock,
    itemStatus,
  ];
}
