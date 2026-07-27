import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  final String userId;
  final String role;
  final String? branchName;
  final String? zone;
  final bool isActive;

  const AppUser({
    required this.userId,
    required this.role,
    this.branchName,
    this.zone,
    required this.isActive,
  });

  @override
  List<Object?> get props => [userId, role, branchName, zone, isActive];
}
