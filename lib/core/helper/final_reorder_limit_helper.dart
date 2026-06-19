class FinalReorderLimitHelper {
  static int capForThisBranch({
    required int oldSafe,
    required int storeStock,
    required int reorderQtyNum,
    required int totalReorderToday,
    required num orderIncreaseLimit,
  }) {
    if (reorderQtyNum > oldSafe) {
      return oldSafe;
    }

    final availableStock = (storeStock - totalReorderToday).clamp(0, 999999999);

    final extra = (availableStock * (orderIncreaseLimit / 100)).ceil();

    return oldSafe + extra;
  }
}
