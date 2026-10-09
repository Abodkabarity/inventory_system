import 'dart:async';

import 'package:daily_order/presentation/inventory_dashboard/widgets/branch_tracker_badge_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the saved instant and excludes already-seen changes', () async {
    final seenAt = DateTime.parse('2026-10-09T14:00:00+04:00');
    DateTime? cutoff;
    bool? inclusive;
    final controller = BranchTrackerBadgeController(
      loadCount: (since, includeBoundary) async {
        cutoff = since;
        inclusive = includeBoundary;
        return 12;
      },
    );
    addTearDown(controller.dispose);

    await controller.initialize(seenAt);

    expect(cutoff, seenAt.toUtc());
    expect(cutoff!.isUtc, isTrue);
    expect(inclusive, isFalse);
    expect(controller.count, 12);
    expect(controller.loading, isFalse);
  });

  test('first visit keeps the inclusive 29-day midnight cutoff', () async {
    final now = DateTime(2026, 10, 9, 15, 45);
    DateTime? cutoff;
    bool? includeBoundary;
    final controller = BranchTrackerBadgeController(
      now: () => now,
      loadCount: (since, inclusive) async {
        cutoff = since;
        includeBoundary = inclusive;
        return 1000;
      },
    );
    addTearDown(controller.dispose);

    await controller.initialize(null);

    expect(cutoff, DateTime(2026, 9, 10).toUtc());
    expect(includeBoundary, isTrue);
    expect(controller.count, 1000);
  });

  testWidgets('groups a burst and does not starve during continuous events', (
    tester,
  ) async {
    var requests = 0;
    final controller = BranchTrackerBadgeController(
      loadCount: (_, _) async => ++requests,
    );
    addTearDown(controller.dispose);
    await controller.initialize(null);

    for (var i = 0; i < 100; i++) {
      controller.scheduleRefresh();
    }
    await tester.pump(const Duration(seconds: 1));
    controller.scheduleRefresh();
    await tester.pump(const Duration(seconds: 1));
    controller.scheduleRefresh();
    expect(requests, 1);
    await tester.pump(const Duration(seconds: 1));

    expect(requests, 2);
    expect(controller.count, 2);
  });

  testWidgets('serializes requests and follows up on events during a request', (
    tester,
  ) async {
    final first = Completer<int>();
    var requests = 0;
    final controller = BranchTrackerBadgeController(
      loadCount: (_, _) {
        requests++;
        return requests == 1 ? first.future : Future.value(7);
      },
    );
    addTearDown(controller.dispose);
    final initialization = controller.initialize(null);
    controller.scheduleRefresh();
    await tester.pump(const Duration(seconds: 3));
    expect(requests, 1);

    first.complete(4);
    await initialization;
    await tester.pump(const Duration(seconds: 3));

    expect(requests, 2);
    expect(controller.count, 7);
  });

  testWidgets('marking seen cannot be undone by an older response', (
    tester,
  ) async {
    final first = Completer<int>();
    final seenAt = DateTime.utc(2026, 10, 9, 12);
    var requests = 0;
    DateTime? secondCutoff;
    bool? secondInclusive;
    final controller = BranchTrackerBadgeController(
      loadCount: (since, inclusive) {
        requests++;
        if (requests == 1) return first.future;
        secondCutoff = since;
        secondInclusive = inclusive;
        return Future.value(2);
      },
    );
    addTearDown(controller.dispose);
    final initialization = controller.initialize(null);
    controller.markSeen(seenAt);
    first.complete(900);
    await initialization;
    expect(controller.count, 0);

    await tester.pump(const Duration(seconds: 3));
    expect(requests, 2);
    expect(secondCutoff, seenAt);
    expect(secondInclusive, isFalse);
    expect(controller.count, 2);
  });

  testWidgets('keeps the last count on failure and recovers on a later event', (
    tester,
  ) async {
    var requests = 0;
    final controller = BranchTrackerBadgeController(
      loadCount: (_, _) async {
        requests++;
        if (requests == 2) throw StateError('Temporary API failure');
        return requests == 1 ? 8 : 11;
      },
    );
    addTearDown(controller.dispose);
    await controller.initialize(null);
    controller.scheduleRefresh();
    await tester.pump(const Duration(seconds: 3));
    expect(controller.count, 8);

    controller.scheduleRefresh();
    await tester.pump(const Duration(seconds: 3));
    expect(controller.count, 11);
  });

  testWidgets('disposal cancels queued work and ignores a pending response', (
    tester,
  ) async {
    final result = Completer<int>();
    var requests = 0;
    var notifications = 0;
    final controller = BranchTrackerBadgeController(
      loadCount: (_, _) {
        requests++;
        return result.future;
      },
    )..addListener(() => notifications++);
    final initialization = controller.initialize(null);
    controller.scheduleRefresh();
    controller.dispose();
    result.complete(5);
    await initialization;
    await tester.pump(const Duration(seconds: 4));

    expect(requests, 1);
    expect(notifications, 0);
  });
}
