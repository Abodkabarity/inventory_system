import 'package:equatable/equatable.dart';
import '../../core/config/tibah_max_config.dart';

enum TibahOrderType {
  upp('UPP'),
  regular('Regular');

  const TibahOrderType(this.label);
  final String label;
  String get branchName =>
      this == TibahOrderType.upp ? 'tibah upp' : 'tibah regular';
  String get branchTitle =>
      this == TibahOrderType.upp ? 'Tibah UPP' : 'Tibah Regular';

  static TibahOrderType? forBranch(String branch) =>
      switch (branch.trim().toLowerCase()) {
        'tibah upp' => TibahOrderType.upp,
        'tibah regular' => TibahOrderType.regular,
        _ => null,
      };

  String printLabel(bool isGeneral) =>
      '$label ${isGeneral ? 'General' : 'Medicine'}';
}

class TibahOrder extends Equatable {
  const TibahOrder({
    required this.id,
    required this.branch,
    required this.type,
    required this.state,
    required this.total,
    required this.prepared,
    this.uploadedAt,
    this.runDate,
  });

  factory TibahOrder.fromJson(Map<String, dynamic> json) => TibahOrder(
    id: json['id'] as String,
    branch: json['branch'] as String,
    type: switch (json['order_type']) {
      'UPP' => TibahOrderType.upp,
      'Regular' => TibahOrderType.regular,
      _ => throw const FormatException('Unknown Tibah order type.'),
    },
    state: json['state'] as String,
    total: (json['total'] as num).toInt(),
    prepared: (json['prepared'] as num).toInt(),
    uploadedAt: DateTime.tryParse(json['uploaded_at']?.toString() ?? ''),
    runDate: json['run_date']?.toString(),
  );

  final String id;
  final String branch;
  final TibahOrderType type;
  final String state;
  final int total;
  final int prepared;
  final DateTime? uploadedAt;
  final String? runDate;
  bool get isReady => state == 'ready';
  bool get isPending => state == 'preparing' || isReady;

  static bool isBranch(String branch) =>
      TibahMaxConfig.enabled && TibahOrderType.forBranch(branch) != null;

  @override
  List<Object?> get props => [
    id,
    branch,
    type,
    state,
    total,
    prepared,
    uploadedAt,
    runDate,
  ];
}
