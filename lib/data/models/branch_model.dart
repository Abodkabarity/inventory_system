import '../../domain/entities/branch.dart';

class BranchModel extends Branch {
  const BranchModel({required super.id, required super.branchName, super.zone});

  factory BranchModel.fromMap(Map<String, dynamic> map) {
    return BranchModel(
      id: map['id'] as String,
      branchName: (map['branch_name'] as String?) ?? '',
      zone: map['zone'] as String?,
    );
  }
}
