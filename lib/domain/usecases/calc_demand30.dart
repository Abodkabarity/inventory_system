import '../entities/calc_input.dart';

class CalcDemand30 {
  const CalcDemand30();

  int call(CalcInput input) {
    final f = input.formulary.trim().toLowerCase();
    final r = input.reason.trim().toLowerCase();

    final maxAdj = _toNum(input.maxAdjustment30d);
    final assortment = _toNum(input.assortmentQtyBaseStock);
    final sales = _toNum(input.sales30dFrom45d);
    final tma = _toNum(input.tmaQty);

    double maxVal;

    final hasMaxAdj = maxAdj.isFinite && maxAdj >= 0;
    final tmaIsZero = tma == 0;
    final tmaIsPresent = tma != 0;

    if (input.formulary.trim() == 'ESSENTIAL' && tmaIsZero && hasMaxAdj) {
      maxVal = maxAdj;
    } else if (f == 'non') {
      if (r == 'new item' && tmaIsZero) {
        maxVal = assortment;
      } else if (tmaIsZero) {
        maxVal = 0;
      } else {
        maxVal = _max4(maxAdj, assortment, sales, tma);
      }
    } else if (maxAdj > 0 && tmaIsZero) {
      maxVal = maxAdj;
    } else if (maxAdj == 0 && tmaIsZero) {
      maxVal = _max2(assortment, sales);
    } else if (tmaIsPresent) {
      maxVal = _max4(maxAdj, assortment, sales, tma);
    } else {
      maxVal = _max4(maxAdj, assortment, sales, tma);
    }

    return _roundUpToInt(maxVal);
  }

  double _toNum(num v) => v.toDouble();

  int _roundUpToInt(double v) {
    if (!v.isFinite) return 0;
    if (v <= 0) return 0;
    return v.ceil();
  }

  double _max2(double a, double b) => a >= b ? a : b;

  double _max4(double a, double b, double c, double d) {
    var m = a;
    if (b > m) m = b;
    if (c > m) m = c;
    if (d > m) m = d;
    if (!m.isFinite) return 0;
    return m;
  }
}
