import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_order/core/config/all_branches_trial_config.dart';
import 'package:daily_order/core/config/online_overview_local_config.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/all_branches_trial_page.dart';

void main() {
  test('approved study is enabled only for the exact original user', () {
    expect(AllBranchesTrialConfig.enabled, isTrue);
    expect(
      AllBranchesTrialConfig.canAccess(OnlineOverviewLocalConfig.allowedUserId),
      isTrue,
    );
    for (final id in [
      null,
      '',
      'another-user',
      OnlineOverviewLocalConfig.allowedUserId.toUpperCase(),
    ]) {
      expect(AllBranchesTrialConfig.canAccess(id), isFalse);
    }
  });
  testWidgets(
    'study renderer never constructs a page without an approved session',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OnlineOverviewTrialSwitch())),
      );
      expect(find.byType(AllBranchesTrialPage), findsNothing);
      expect(find.text('All branches'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
