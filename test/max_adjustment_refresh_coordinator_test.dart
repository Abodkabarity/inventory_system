import 'package:daily_order/core/utils/max_adjustment_refresh_coordinator.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'changes during the final import read cause one follow-up refresh',
    () => fakeAsync((clock) {
      var calls = 0;
      final refresh = MaxAdjustmentRefreshCoordinator(onRefresh: () => calls++);
      refresh.pause();
      for (var i = 0; i < 10000; i++) {
        refresh.changed();
      }
      refresh.beginLoad();
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 0);
      refresh.changed();
      refresh.changed();
      refresh.resume();
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      refresh.dispose();
    }),
  );
  test(
    'coalesces 10000 row notifications into one refresh',
    () => fakeAsync((clock) {
      var calls = 0;
      final refresh = MaxAdjustmentRefreshCoordinator(onRefresh: () => calls++);
      for (var i = 0; i < 10000; i++) {
        refresh.changed();
      }
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      clock.elapse(const Duration(seconds: 10));
      expect(calls, 1);
      refresh.dispose();
    }),
  );
  test(
    'import pauses notifications and discards changes covered by final server read',
    () => fakeAsync((clock) {
      var calls = 0;
      final refresh = MaxAdjustmentRefreshCoordinator(onRefresh: () => calls++);
      refresh.changed();
      refresh.pause();
      for (var i = 0; i < 10000; i++) {
        refresh.changed();
      }
      clock.elapse(const Duration(seconds: 10));
      expect(calls, 0);
      refresh.resume(alreadyRefreshed: true);
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 0);
      refresh.changed(); // late delivery is still coalesced and refreshed.
      refresh.changed();
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      refresh.dispose();
    }),
  );
  test(
    'notifications never restart a running full refresh',
    () => fakeAsync((clock) {
      var calls = 0;
      final refresh = MaxAdjustmentRefreshCoordinator(onRefresh: () => calls++);
      refresh.beginLoad();
      for (var i = 0; i < 10000; i++) {
        refresh.changed();
      }
      clock.elapse(const Duration(seconds: 5));
      expect(calls, 0);
      refresh.endLoad();
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      refresh.dispose();
    }),
  );
  test(
    'cancelled import resumes pending external updates; dispose cancels timers',
    () => fakeAsync((clock) {
      var calls = 0;
      final refresh = MaxAdjustmentRefreshCoordinator(onRefresh: () => calls++);
      refresh.pause();
      refresh.changed();
      refresh.resume();
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      refresh.changed();
      refresh.dispose();
      refresh.changed();
      clock.elapse(const Duration(seconds: 10));
      expect(calls, 1);
    }),
  );
}
