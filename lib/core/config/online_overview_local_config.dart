import 'package:supabase_flutter/supabase_flutter.dart';

/// User-scoped rollout explicitly approved on 2026-11-19.
/// The server independently enforces this same user ID for every feature RPC.
abstract final class OnlineOverviewLocalConfig {
  static const batchSize = 5000;
  // Recorded-sales update explicitly approved for this same account on 2026-11-20.
  // Navigation, route rendering and every server request enforce allowedUserId.
  static const actualSalesPreview = true;
  static const allowedUserId = '94c7aa76-bc23-40e4-8c9a-f2cb9636c821';
  static bool canAccess(String? userId) => userId == allowedUserId;
  static String? get currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static Stream<AuthState>? get authChanges {
    try {
      return Supabase.instance.client.auth.onAuthStateChange;
    } catch (_) {
      return null;
    }
  }
}
