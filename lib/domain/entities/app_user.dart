import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  final String userId;
  final String role;
  final String? branchName;
  final String? zone;
  final List<String> zones;
  final bool isActive;

  const AppUser({
    required this.userId,
    required this.role,
    this.branchName,
    this.zone,
    this.zones = const [],
    required this.isActive,
  });

  List<String> get effectiveZones {
    final values =
        <String>{
          ...zones
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty),
          if ((zone ?? '').trim().isNotEmpty) zone!.trim(),
        }.toList(growable: false)..sort(
          (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
        );
    return values;
  }

  @override
  List<Object?> get props => [userId, role, branchName, zone, zones, isActive];
}
