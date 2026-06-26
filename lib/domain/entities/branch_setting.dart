import 'dart:convert';

import 'package:equatable/equatable.dart';

class BranchSetting extends Equatable {
  final String branchName;
  final String email;
  final String zone;
  final bool isActive;
  final List<String> orderDays;
  final int submitStartHour;
  final int submitEndHour;
  final int maxAdjLimit;
  final int orderIncreaseLimit;
  final int orderEditLimit;
  final int additionalOrderLimit;
  final String area;
  final String branchType;

  const BranchSetting({
    required this.branchName,
    required this.email,
    required this.zone,
    required this.isActive,
    required this.orderDays,
    required this.submitStartHour,
    required this.submitEndHour,
    required this.maxAdjLimit,
    required this.orderIncreaseLimit,
    required this.orderEditLimit,
    required this.additionalOrderLimit,
    required this.area,
    required this.branchType,
  });

  factory BranchSetting.empty() {
    return const BranchSetting(
      branchName: '',
      email: '',
      zone: '',
      isActive: true,
      orderDays: [],
      submitStartHour: 21,
      submitEndHour: 8,
      maxAdjLimit: 50,
      orderIncreaseLimit: 10,
      orderEditLimit: 50,
      additionalOrderLimit: 15,
      area: '',
      branchType: '',
    );
  }

  factory BranchSetting.fromMap(Map<String, dynamic> map) {
    return BranchSetting(
      branchName: (map['branch_name'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      zone: (map['zone'] ?? '').toString(),
      isActive: _bool(map['is_active']),
      orderDays: _days(map['order_days']),
      submitStartHour: _int(map['submit_start_hour'], 21),
      submitEndHour: _int(map['submit_end_hour'], 8),
      maxAdjLimit: _int(map['max_adj_limit'], 50),
      orderIncreaseLimit: _int(map['order_increase_limit'], 10),
      orderEditLimit: _int(map['order_edit_limit'], 50),
      additionalOrderLimit: _int(map['additional_order_limit'], 15),
      area: (map['area'] ?? '').toString(),
      branchType: (map['branch_type'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'branch_name': branchName.trim(),
      'email': email.trim(),
      'zone': zone.trim(),
      'is_active': isActive,
      'order_days': orderDays,
      'submit_start_hour': submitStartHour,
      'submit_end_hour': submitEndHour,
      'max_adj_limit': maxAdjLimit,
      'order_increase_limit': orderIncreaseLimit,
      'order_edit_limit': orderEditLimit,
      'additional_order_limit': additionalOrderLimit,
      'area': area.trim(),
      'branch_type': branchType.trim(),
    };
  }

  BranchSetting copyWith({
    String? branchName,
    String? email,
    String? zone,
    bool? isActive,
    List<String>? orderDays,
    int? submitStartHour,
    int? submitEndHour,
    int? maxAdjLimit,
    int? orderIncreaseLimit,
    int? orderEditLimit,
    int? additionalOrderLimit,
    String? area,
    String? branchType,
  }) {
    return BranchSetting(
      branchName: branchName ?? this.branchName,
      email: email ?? this.email,
      zone: zone ?? this.zone,
      isActive: isActive ?? this.isActive,
      orderDays: orderDays ?? this.orderDays,
      submitStartHour: submitStartHour ?? this.submitStartHour,
      submitEndHour: submitEndHour ?? this.submitEndHour,
      maxAdjLimit: maxAdjLimit ?? this.maxAdjLimit,
      orderIncreaseLimit: orderIncreaseLimit ?? this.orderIncreaseLimit,
      orderEditLimit: orderEditLimit ?? this.orderEditLimit,
      additionalOrderLimit: additionalOrderLimit ?? this.additionalOrderLimit,
      area: area ?? this.area,
      branchType: branchType ?? this.branchType,
    );
  }

  static int _int(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  static List<String> _days(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {
        return value
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    final s = (value ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  @override
  List<Object?> get props => [
    branchName,
    email,
    zone,
    isActive,
    orderDays,
    submitStartHour,
    submitEndHour,
    maxAdjLimit,
    orderIncreaseLimit,
    orderEditLimit,
    additionalOrderLimit,
    area,
    branchType,
  ];
}
