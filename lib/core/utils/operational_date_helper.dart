class OperationalDateHelper {
  static const bool debugMode = false;

  static const int debugHourOffset = -1;

  static DateTime get nowUae {
    final real = DateTime.now().toUtc().add(
      const Duration(hours: 4),
    );

    if (!debugMode) {
      return real;
    }

    return real.add(
      Duration(hours: debugHourOffset),
    );
  }

  // ==========================
  // OPERATIONAL DATE
  // ==========================
  static DateTime get operationalNow {
    final now = nowUae;

    if (now.hour >= 21) {
      return now.add(const Duration(days: 1));
    }

    return now;
  }

  static String get operationalDate {
    final d = operationalNow;

    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');

    return '$y-$m-$day';
  }

  // ==========================
  // DEFAULT SYSTEM WINDOW
  // ==========================
  static bool get canSubmit {
    final hour = nowUae.hour;

    return hour >= 21 || hour < 9;
  }

  static bool get isAfter9Pm {
    return nowUae.hour >= 21;
  }

  static bool get isMissingOrderWindow {
    final hour = nowUae.hour;

    return hour >= 9 && hour < 21;
  }

  // ==========================
  // CUSTOM BRANCH WINDOW
  // ==========================
  static bool canSubmitForBranch({
    required int startHour,
    required int endHour,
  }) {
    final hour = nowUae.hour;

    if (startHour == 0 && endHour == 24) {
      return true;
    }


    if (startHour > endHour) {
      return hour >= startHour || hour < endHour;
    }


    return hour >= startHour &&
        hour < endHour;
  }

  static bool isMissingWindowForBranch({
    required int startHour,
    required int endHour,
  }) {
    return !canSubmitForBranch(
      startHour: startHour,
      endHour: endHour,
    );
  }

  static bool isAfterSubmitStartForBranch({
    required int startHour,
  }) {
    return nowUae.hour >= startHour;
  }
}