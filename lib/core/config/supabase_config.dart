class SupabaseConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  // Development-only override for the assistant function. All other data and
  // authentication requests remain on the configured Supabase project.
  static const localInsuranceAssistantUrl = String.fromEnvironment(
    'LOCAL_INSURANCE_ASSISTANT_URL',
  );

  static Uri? get localInsuranceAssistantUri {
    final value = localInsuranceAssistantUrl.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('LOCAL_INSURANCE_ASSISTANT_URL must be a complete URL.');
    }
    // A production build must never accidentally send an authenticated session
    // token to an arbitrary host. The local adapter is intentionally limited
    // to this machine during the development phase.
    const localHosts = {'localhost', '127.0.0.1', '::1'};
    if (!localHosts.contains(uri.host)) {
      throw StateError(
        'LOCAL_INSURANCE_ASSISTANT_URL is allowed only for localhost during local development.',
      );
    }
    return uri;
  }

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
