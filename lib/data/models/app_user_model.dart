import '../../domain/entities/app_user.dart';

class AppUserModel extends AppUser {
  const AppUserModel({
    required super.userId,
    required super.role,
    super.branchName,
    super.zone,
    required super.isActive,
  });

  factory AppUserModel.fromMap(Map<String, dynamic> map) {
    return AppUserModel(
      userId: map['user_id'] as String,
      role: (map['role'] as String?) ?? '',
      branchName: map['branch_name'] as String?, // <-- important change
      zone: map['zone'] as String?,
      isActive: (map['is_active'] as bool?) ?? true,
    );
  }
}
