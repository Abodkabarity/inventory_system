import '../entities/app_user.dart';

abstract class AuthRepository {
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  AppUser? getCurrentUserBasic(); // from auth.users
  Future<AppUser?> getMe(); // from app_users
}
