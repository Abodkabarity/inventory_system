import 'package:equatable/equatable.dart';

class ItemToOrder extends Equatable {
  final String id;

  final String itemCode;
  final String itemName;

  final num qty;

  final String reason;

  final String status;

  final String? createdBy;

  final DateTime createdAt;

  const ItemToOrder({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.createdBy,
  });

  factory ItemToOrder.fromMap(Map<String, dynamic> map) {
    return ItemToOrder(
      id: (map['id'] ?? '').toString(),
      itemCode: (map['item_code'] ?? '').toString(),
      itemName: (map['item_name'] ?? '').toString(),
      qty: num.tryParse((map['qty'] ?? '0').toString()) ?? 0,
      reason: (map['reason'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      createdBy: map['created_by']?.toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    itemCode,
    itemName,
    qty,
    reason,
    status,
    createdBy,
    createdAt,
  ];
}
