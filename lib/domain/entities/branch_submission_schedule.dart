import 'package:equatable/equatable.dart';

class BranchSubmissionSchedule extends Equatable {
  final String branchName;
  final DateTime effectiveFrom;
  final List<String> orderDays;
  final int submitStartHour;
  final int submitEndHour;

  const BranchSubmissionSchedule({
    required this.branchName,
    required this.effectiveFrom,
    required this.orderDays,
    required this.submitStartHour,
    required this.submitEndHour,
  });

  factory BranchSubmissionSchedule.fromMap(Map<String, dynamic> map) {
    return BranchSubmissionSchedule(
      branchName: (map['branch_name'] ?? '').toString(),
      effectiveFrom:
          DateTime.tryParse((map['effective_from'] ?? '').toString()) ??
          DateTime(1900),
      orderDays: (map['order_days'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      submitStartHour: _int(map['submit_start_hour'], 21),
      submitEndHour: _int(map['submit_end_hour'], 8),
    );
  }

  static int _int(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  @override
  List<Object?> get props => [
    branchName,
    effectiveFrom,
    orderDays,
    submitStartHour,
    submitEndHour,
  ];
}
