import 'package:equatable/equatable.dart';

class StoreOrderItem extends Equatable {
  final String itemCode;
  final String itemName;
  final String barcode;
  final String supplier;

  final String classification;
  final String category;

  final num quantity;

  const StoreOrderItem({
    required this.itemCode,
    required this.itemName,
    required this.barcode,
    required this.supplier,
    required this.classification,
    required this.category,
    required this.quantity,
  });

  List<Object?> get props => [
    itemCode,
    itemName,
    barcode,
    supplier,
    classification,
    category,
    quantity,
  ];
}
