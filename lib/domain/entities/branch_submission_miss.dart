import 'package:equatable/equatable.dart';

class BranchSubmissionMiss extends Equatable {
  final String id;
  final DateTime runDate;
  final String branchName;
  final String zone;
  final String zoneManager;
  final String zoneManagerEmail;
  final String area;
  final String branchType;
  final DateTime expectedSubmitBy;
  final DateTime? submittedAt;
  final String status;
  final int minutesLate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BranchSubmissionMiss({
    required this.id,
    required this.runDate,
    required this.branchName,
    required this.zone,
    required this.zoneManager,
    required this.zoneManagerEmail,
    required this.area,
    required this.branchType,
    required this.expectedSubmitBy,
    required this.submittedAt,
    required this.status,
    required this.minutesLate,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isLateSubmitted => status == 'late_submitted';
  bool get isNotSubmitted => status == 'not_submitted';

  factory BranchSubmissionMiss.fromMap(Map<String, dynamic> map) {
    return BranchSubmissionMiss(
      id: (map['id'] ?? '').toString(),
      runDate:
          DateTime.tryParse((map['run_date'] ?? '').toString()) ??
          DateTime(1900),
      branchName: (map['branch_name'] ?? '').toString(),
      zone: (map['zone'] ?? '').toString(),
      zoneManager: (map['zone_manager'] ?? '').toString(),
      zoneManagerEmail: (map['zone_manager_email'] ?? '').toString(),
      area: (map['area'] ?? '').toString(),
      branchType: (map['branch_type'] ?? '').toString(),
      expectedSubmitBy:
          DateTime.tryParse((map['expected_submit_by'] ?? '').toString()) ??
          DateTime(1900),
      submittedAt: DateTime.tryParse((map['submitted_at'] ?? '').toString()),
      status: (map['status'] ?? 'not_submitted').toString(),
      minutesLate: _int(map['minutes_late']),
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()),
    );
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  @override
  List<Object?> get props => [
    id,
    runDate,
    branchName,
    zone,
    zoneManager,
    zoneManagerEmail,
    area,
    branchType,
    expectedSubmitBy,
    submittedAt,
    status,
    minutesLate,
    createdAt,
    updatedAt,
  ];
}
