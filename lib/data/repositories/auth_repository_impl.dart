import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/remote/supabase_auth_remote_ds.dart';

class AuthRepositoryImpl implements AuthRepository {
  final SupabaseAuthRemoteDs ds;
  AuthRepositoryImpl(this.ds);

  @override
  Future<void> signIn(String email, String password) =>
      ds.signIn(email, password);

  @override
  Future<void> signOut() => ds.signOut();

  @override
  AppUser? getCurrentUserBasic() {
    final u = ds.currentUser();
    if (u == null) return null;

    return AppUser(
      userId: u.id,
      role: 'unknown',
      branchName: null,
      isActive: true,
    );
  }

  @override
  Future<AppUser?> getMe() => ds.getMeFromAppUsers();
}
