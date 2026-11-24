import 'online_overview_local_config.dart';

/// Study rollout explicitly approved on 2026-11-24 for the original account only.
abstract final class AllBranchesTrialConfig {
  static const enabled = true;
  static bool canAccess(String? userId) =>
      enabled && OnlineOverviewLocalConfig.canAccess(userId);
}
