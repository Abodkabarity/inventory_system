import 'package:flutter/material.dart';
import '../../../core/config/online_overview_local_config.dart';

/// Removes the page and its in-memory results immediately on sign-out/account change.
class OnlineOverviewUserGate extends StatelessWidget {
  final Widget child;
  const OnlineOverviewUserGate({super.key, required this.child});
  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: OnlineOverviewLocalConfig.authChanges,
    builder: (context, _) =>
        OnlineOverviewLocalConfig.canAccess(
          OnlineOverviewLocalConfig.currentUserId,
        )
        ? KeyedSubtree(
            key: ValueKey(OnlineOverviewLocalConfig.currentUserId),
            child: child,
          )
        : const SizedBox.shrink(),
  );
}
