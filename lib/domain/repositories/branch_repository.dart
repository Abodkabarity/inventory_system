import '../entities/branch.dart';

abstract class BranchRepository {
  Future<Branch?> getBranchById(String branchId);
}
