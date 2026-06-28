class FinalReorderLimitHelper {
  static int capForThisBranch({
    required int oldSafe,
    required int storeStock,
    required int reorderQtyNum,
    required int totalReorderToday,
    required num orderIncreaseLimit,
    int orderStep = 1,
  }) {
    if (reorderQtyNum > oldSafe) {
      return oldSafe;
    }

    final availableStock = (storeStock - totalReorderToday).clamp(0, 999999999);

    final extra = (availableStock * (orderIncreaseLimit / 100)).ceil();

    final rawCap = oldSafe + extra;
    final step = orderStep <= 1 ? 1 : orderStep;

    if (step == 1) return rawCap;

    return (rawCap ~/ step) * step;
  }
}
