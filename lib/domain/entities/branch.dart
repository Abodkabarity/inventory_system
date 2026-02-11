import 'package:equatable/equatable.dart';

class Branch extends Equatable {
  final String id;
  final String branchName;
  final String? zone;

  const Branch({required this.id, required this.branchName, this.zone});

  @override
  List<Object?> get props => [id, branchName, zone];
}
