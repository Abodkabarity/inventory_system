class SupabaseConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static void validate() {
    final missing = <String>[
      if (supabaseUrl.trim().isEmpty) 'SUPABASE_URL',
      if (anonKey.trim().isEmpty) 'SUPABASE_ANON_KEY',
    ];

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required Supabase configuration: ${missing.join(', ')}. '
        'Pass them with --dart-define or --dart-define-from-file.',
      );
    }
  }
}
