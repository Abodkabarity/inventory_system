import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_user_model.dart';

class SupabaseAuthRemoteDs {
  final SupabaseClient client;
  SupabaseAuthRemoteDs(this.client);

  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  User? currentUser() => client.auth.currentUser;

  Future<AppUserModel?> getMeFromAppUsers() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return null;

    final data = await client
        .from('app_users')
        .select('user_id, role, branch_name, zone, is_active')
        .eq('user_id', uid)
        .maybeSingle();

    if (data == null) return null;

    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    final isActive = (data['is_active'] as bool?) ?? true;
    final branchName = (data['branch_name'] ?? '').toString().trim();
    final zone = (data['zone'] ?? '').toString().trim();

    if (!isActive) {
      throw Exception('This user is inactive in app_users.');
    }

    if (role == 'zone_manager') {
      final zones = <String>{};
      var authoritativeAssignmentsLoaded = false;
      try {
        final effective = List<Map<String, dynamic>>.from(
          await client.rpc('get_my_effective_zones'),
        );
        authoritativeAssignmentsLoaded = true;
        zones.addAll(
          effective
              .map((row) => (row['zone'] ?? '').toString().trim())
              .where((value) => value.isNotEmpty),
        );
      } catch (_) {
        try {
          final assigned = List<Map<String, dynamic>>.from(
            await client
                .from('app_user_zones')
                .select('zone')
                .eq('user_id', uid),
          );
          authoritativeAssignmentsLoaded = assigned.isNotEmpty;
          zones.addAll(
            assigned
                .map((row) => (row['zone'] ?? '').toString().trim())
                .where((value) => value.isNotEmpty),
          );
        } catch (_) {
          // The legacy app_users.zone is applied below only when no authoritative
          // multi-zone assignment can be loaded.
        }
      }
      if (!authoritativeAssignmentsLoaded && zones.isEmpty && zone.isNotEmpty) {
        zones.add(zone);
      }
      if (zones.isEmpty) {
        throw Exception('No zone assigned for this Zone Manager.');
      }
      return AppUserModel.fromMap({
        'user_id': data['user_id'],
        'role': data['role'],
        'branch_name': null,
        'zone': zone,
        'zones': zones.toList(growable: false),
        'is_active': isActive,
      });
    }

    // Other back-office roles do not require a branch assignment.
    if (role == 'inventory' || role == 'purchase') {
      return AppUserModel.fromMap({
        'user_id': data['user_id'],
        'role': data['role'],
        'branch_name': null,
        'zone': null,
        'is_active': isActive,
      });
    }

    // Other roles MUST have branch_name
    if (branchName.isEmpty) {
      throw Exception('No branch assigned for this user in app_users.');
    }

    return AppUserModel.fromMap(data);
  }
}
