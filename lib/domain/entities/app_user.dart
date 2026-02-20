import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  final String userId;
  final String role;
  final String? branchName;
  final bool isActive;

  const AppUser({
    required this.userId,
    required this.role,
    this.branchName,
    required this.isActive,
  });

  @override
  List<Object?> get props => [userId, role, branchName, isActive];
}
