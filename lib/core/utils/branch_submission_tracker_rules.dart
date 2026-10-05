import '../../domain/entities/branch_setting.dart';
import '../../domain/entities/branch_submission_schedule.dart';

DateTime submissionTrackerMonthStart(DateTime now) {
  return DateTime(now.year, now.month);
}

bool shouldTrackBranchSubmissionOn({
  required BranchSetting branch,
  required DateTime runDate,
  required DateTime trackerActivationAt,
}) {
  final day = DateTime(runDate.year, runDate.month, runDate.day);
  final configuredStart =
      branch.submissionTrackingStartedOn ?? trackerActivationAt;
  final branchStart = DateTime(
    configuredStart.year,
    configuredStart.month,
    configuredStart.day,
  );
  return !day.isBefore(branchStart) && !day.isBefore(trackerActivationAt);
}

String branchSubmissionStatusLabel(String status) {
  return status == 'late_submitted'
      ? 'Submitted after deadline'
      : 'Not submitted by branch';
}

BranchSubmissionSchedule? submissionScheduleForDate(
  Iterable<BranchSubmissionSchedule> schedules,
  DateTime runDate,
) {
  final day = DateTime(runDate.year, runDate.month, runDate.day);
  BranchSubmissionSchedule? result;
  for (final schedule in schedules) {
    final effectiveFrom = DateTime(
      schedule.effectiveFrom.year,
      schedule.effectiveFrom.month,
      schedule.effectiveFrom.day,
    );
    if (effectiveFrom.isAfter(day)) continue;
    if (result == null || effectiveFrom.isAfter(result.effectiveFrom)) {
      result = schedule;
    }
  }
  return result;
}
