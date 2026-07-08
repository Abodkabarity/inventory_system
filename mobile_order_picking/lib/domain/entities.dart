import 'package:equatable/equatable.dart';

enum PickCategory {
  medicine('Medicine'),
  general('General');

  final String label;
  const PickCategory(this.label);
}

class BranchOption extends Equatable {
  final String name;
  const BranchOption(this.name);

  @override
  List<Object?> get props => [name];
}

class MobileOrderItem extends Equatable {
  final String movementId;
  final String branch;
  final DateTime movementDate;
  final String itemCode;
  final String itemName;
  final String barcode;
  final List<String> validBarcodes;
  final String supplier;
  final String category;
  final String classification;
  final num expectedQty;
  final String sourceId;

  const MobileOrderItem({
    required this.movementId,
    required this.branch,
    required this.movementDate,
    required this.itemCode,
    required this.itemName,
    required this.barcode,
    required this.validBarcodes,
    required this.supplier,
    required this.category,
    required this.classification,
    required this.expectedQty,
    required this.sourceId,
  });

  factory MobileOrderItem.fromJson(Map<String, dynamic> json) {
    return MobileOrderItem(
      movementId: (json['movementId'] ?? '').toString(),
      branch: (json['branch'] ?? '').toString(),
      movementDate:
          DateTime.tryParse((json['movementDate'] ?? '').toString()) ??
          DateTime.now(),
      itemCode: (json['itemCode'] ?? '').toString(),
      itemName: (json['itemName'] ?? '').toString(),
      barcode: (json['barcode'] ?? '').toString(),
      validBarcodes: List<dynamic>.from(
        (json['validBarcodes'] as List?) ?? const [],
      ).map((e) => e.toString()).toList(),
      supplier: (json['supplier'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      classification: (json['classification'] ?? '').toString(),
      expectedQty: _num(json['expectedQty']),
      sourceId: (json['sourceId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'movementId': movementId,
      'branch': branch,
      'movementDate': movementDate.toIso8601String(),
      'itemCode': itemCode,
      'itemName': itemName,
      'barcode': barcode,
      'validBarcodes': validBarcodes,
      'supplier': supplier,
      'category': category,
      'classification': classification,
      'expectedQty': expectedQty,
      'sourceId': sourceId,
    };
  }

  PickCategory get pickCategory {
    return classification.toLowerCase().contains('general')
        ? PickCategory.general
        : PickCategory.medicine;
  }

  @override
  List<Object?> get props => [
    movementId,
    branch,
    movementDate,
    itemCode,
    itemName,
    barcode,
    validBarcodes,
    supplier,
    category,
    classification,
    expectedQty,
    sourceId,
  ];
}

class PickedItem extends Equatable {
  final String itemCode;
  final num pickedQty;
  final String scannedBarcode;
  final DateTime pickedAt;

  const PickedItem({
    required this.itemCode,
    required this.pickedQty,
    required this.scannedBarcode,
    required this.pickedAt,
  });

  factory PickedItem.fromJson(Map<String, dynamic> json) {
    return PickedItem(
      itemCode: (json['itemCode'] ?? '').toString(),
      pickedQty: _num(json['pickedQty']),
      scannedBarcode: (json['scannedBarcode'] ?? '').toString(),
      pickedAt:
          DateTime.tryParse((json['pickedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemCode': itemCode,
      'pickedQty': pickedQty,
      'scannedBarcode': scannedBarcode,
      'pickedAt': pickedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [itemCode, pickedQty, scannedBarcode, pickedAt];
}

num _num(dynamic value) {
  if (value is num) return value;
  return num.tryParse((value ?? '0').toString()) ?? 0;
}
