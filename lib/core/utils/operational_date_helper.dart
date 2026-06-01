class OperationalDateHelper {
  /*
  static DateTime get nowUae {
    return DateTime.now().toUtc().add(const Duration(hours: 4));
  }
*/
  static const bool debugMode = true;

  static const int debugHourOffset = -1;

  static DateTime get nowUae {
    final real = DateTime.now().toUtc().add(const Duration(hours: -5));

    if (!debugMode) {
      return real;
    }

    return real.add(const Duration(hours: debugHourOffset));
  }

  static DateTime get operationalNow {
    final now = nowUae;

    final cutoff = DateTime(now.year, now.month, now.day, 21);

    if (now.isAfter(cutoff)) {
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
    final now = nowUae;

    final hour = now.hour;

    return hour >= 21 || hour < 9;
  }

  static bool get isAfter9Pm {
    return nowUae.hour >= 21;
  }

  static bool get isMissingOrderWindow {
    final now = nowUae;

    final hour = now.hour;

    return hour >= 9 && hour < 21;
  }
}
