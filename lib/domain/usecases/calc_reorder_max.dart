class CalcReorderMax {
  const CalcReorderMax();

  int call(int demand30) {
    final m = demand30.toDouble();

    double v;
    if (m <= 25) {
      v = m;
    } else if (m <= 150) {
      v = (m / 30.0) * 21.0;
    } else {
      v = (m / 30.0) * 14.0;
    }

    return _roundUpToInt(v);
  }

  int _roundUpToInt(double v) {
    if (!v.isFinite) return 0;
    if (v <= 0) return 0;
    return v.ceil();
  }
}
