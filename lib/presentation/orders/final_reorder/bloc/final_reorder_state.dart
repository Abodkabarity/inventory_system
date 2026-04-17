import 'package:equatable/equatable.dart';

class FinalReorderDialogPayload extends Equatable {
  final String title;
  final String body;

  const FinalReorderDialogPayload({required this.title, required this.body});

  @override
  List<Object?> get props => [title, body];
}

class FinalReorderState extends Equatable {
  final int qty;
  final String reason;

  final int oldQty;
  final int storeStock;
  final int reorderQtyNum;
  final int totalReorderToday;
  final bool isNonFormulary;
  final bool isLocked;
  final bool onlyDecrease;

  final int capForThisBranch;

  final bool canIncrease;
  final bool canDecrease;
  final bool hasTma;
  final bool hasChange;
  final bool reasonOk;
  final bool canSave;

  final bool isLimitedStockLive;

  /// if not null -> UI shows dialog then dispatch FinalReorderDialogConsumed
  final FinalReorderDialogPayload? dialog;

  const FinalReorderState({
    required this.qty,
    required this.reason,
    required this.oldQty,
    required this.storeStock,
    required this.reorderQtyNum,
    required this.isNonFormulary,
    required this.isLocked,
    required this.onlyDecrease,
    required this.capForThisBranch,
    required this.canIncrease,
    required this.canDecrease,
    required this.hasChange,
    required this.reasonOk,
    required this.canSave,
    required this.isLimitedStockLive,
    required this.dialog,
    required this.totalReorderToday,
    required this.hasTma,
  });

  FinalReorderState copyWith({
    int? qty,
    String? reason,
    int? oldQty,
    int? storeStock,
    int? reorderQtyNum,
    bool? isNonFormulary,
    bool? isLocked,
    bool? onlyDecrease,
    int? capForThisBranch,
    bool? canIncrease,
    bool? canDecrease,
    bool? hasTma,
    bool? hasChange,
    bool? reasonOk,
    int? totalReorderToday,
    bool? canSave,
    bool? isLimitedStockLive,
    FinalReorderDialogPayload? dialog,
    bool clearDialog = false,
  }) {
    return FinalReorderState(
      qty: qty ?? this.qty,
      reason: reason ?? this.reason,
      oldQty: oldQty ?? this.oldQty,
      storeStock: storeStock ?? this.storeStock,
      reorderQtyNum: reorderQtyNum ?? this.reorderQtyNum,
      isNonFormulary: isNonFormulary ?? this.isNonFormulary,
      isLocked: isLocked ?? this.isLocked,
      onlyDecrease: onlyDecrease ?? this.onlyDecrease,
      capForThisBranch: capForThisBranch ?? this.capForThisBranch,
      canIncrease: canIncrease ?? this.canIncrease,
      canDecrease: canDecrease ?? this.canDecrease,
      hasChange: hasChange ?? this.hasChange,
      reasonOk: reasonOk ?? this.reasonOk,
      canSave: canSave ?? this.canSave,
      isLimitedStockLive: isLimitedStockLive ?? this.isLimitedStockLive,
      dialog: clearDialog ? null : (dialog ?? this.dialog),
      totalReorderToday: totalReorderToday ?? this.totalReorderToday,
      hasTma: hasTma ?? this.hasTma,
    );
  }

  @override
  List<Object?> get props => [
    qty,
    reason,
    oldQty,
    storeStock,
    reorderQtyNum,
    isNonFormulary,
    isLocked,
    onlyDecrease,
    capForThisBranch,
    canIncrease,
    canDecrease,
    hasChange,
    reasonOk,
    canSave,
    isLimitedStockLive,
    dialog,
    totalReorderToday,
    hasTma,
  ];
}
