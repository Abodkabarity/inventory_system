import '../../domain/entities/item.dart';

class ItemModel extends Item {
  const ItemModel({
    required super.itemCode,
    required super.itemName,
    super.barcode,
    super.status,
    required super.isBlock,
    super.itemStatus,
  });

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      itemCode: (map['item_code'] as String?) ?? '',
      itemName: (map['item_name'] as String?) ?? '',
      barcode: map['barcode'] as String?,
      status: map['status'] as String?,
      isBlock: (map['is_block'] as bool?) ?? false,
      itemStatus: map['item_status'] as String?,
    );
  }
}
