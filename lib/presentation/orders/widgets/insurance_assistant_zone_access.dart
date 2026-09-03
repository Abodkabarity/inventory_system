/// Controls where the Insurance Assistant is exposed in the branch order UI.
///
/// This is intentionally a presentation/access rule only. It does not alter
/// order loading, editing, saving, allocation, or submission behavior.
abstract final class InsuranceAssistantZoneAccess {
  static const enabledZone = 'Zone4';

  static bool isEnabled(String? zone) {
    final normalized = (zone ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[\s_-]+'),
      '',
    );
    return normalized == enabledZone.toLowerCase();
  }
}
