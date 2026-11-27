/// Temporary Tibah import/preparation workflow. Set this flag to false and
/// disable the two server controls when retiring it; ordinary Max stays intact.
abstract final class TibahMaxConfig {
  static const enabled = bool.fromEnvironment(
    'TIBAH_MAX_ENABLED',
    defaultValue: true,
  );
}
