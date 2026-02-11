import '../entities/app_user.dart';
import '../repositories/auth_repository.dart';

class GetMe {
  final AuthRepository repo;
  GetMe(this.repo);

  Future<AppUser?> call() => repo.getMe();
}
