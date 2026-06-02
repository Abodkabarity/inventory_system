class OperationalDateHelper {
  static const bool debugMode = false;

  static const int debugHourOffset = -1;

  static DateTime get nowUae {
    final real = DateTime.now().toUtc().add(const Duration(hours: 4));

    if (!debugMode) {
      return real;
    }

    return real.add(Duration(hours: debugHourOffset));
  }

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
}
