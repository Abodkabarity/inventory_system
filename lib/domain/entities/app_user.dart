import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  final String userId;
  final String role;
  final String? branchId;

  const AppUser({required this.userId, required this.role, this.branchId});

  @override
  List<Object?> get props => [userId, role, branchId];
}
