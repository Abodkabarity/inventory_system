class CalcReorderMin {
  const CalcReorderMin();

  int call(int demand30) {
    final m = demand30.toDouble();

    if (demand30 == 1) return 0;

    double v;
    if (m <= 25) {
      v = (m / 30.0) * 21.0;
    } else if (m <= 150) {
      v = (m / 30.0) * 15.0;
    } else {
      v = (m / 30.0) * 10.0;
    }

    return _roundToInt(v);
  }

  int _roundToInt(double v) {
    if (!v.isFinite) return 0;
    return v.round();
  }
}
