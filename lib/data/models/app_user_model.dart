import '../../domain/entities/app_user.dart';

class AppUserModel extends AppUser {
  const AppUserModel({
    required super.userId,
    required super.role,
    super.branchId,
  });

  factory AppUserModel.fromMap(Map<String, dynamic> map) {
    return AppUserModel(
      userId: map['user_id'] as String,
      role: (map['role'] as String?) ?? '',
      branchId: map['branch_id'] as String?,
    );
  }
}
