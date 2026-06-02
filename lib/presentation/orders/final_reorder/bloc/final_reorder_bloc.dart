import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/daily_order_row.dart';
import 'final_reorder_event.dart';
import 'final_reorder_state.dart';

class FinalReorderBloc extends Bloc<FinalReorderEvent, FinalReorderState> {
  final DailyOrderRow row;
  final int oldQtyInput;
  final int compareQtyInput;
  final int initialQtyInput;
  final String initialReasonInput;

  final Future<void> Function(int newQty, String reason) onSave;
  final void Function() onReset;

  FinalReorderBloc({
    required this.row,
    required this.oldQtyInput,
    required this.initialQtyInput,
    required this.initialReasonInput,
    required this.onSave,
    required this.onReset,
    required this.compareQtyInput,
  }) : super(
         _buildInitial(
           row: row,
           oldQtyInput: oldQtyInput,
           initialQtyInput: initialQtyInput,
           compareQtyInput: compareQtyInput,
           initialReasonInput: initialReasonInput,
         ),
       ) {
    on<FinalReorderStarted>(_onStarted);
    on<FinalReorderQtyTextChanged>(_onQtyTextChanged);
    on<FinalReorderIncPressed>(_onInc);
    on<FinalReorderDecPressed>(_onDec);
    on<FinalReorderReasonChanged>(_onReasonChanged);
    on<FinalReorderResetPressed>(_onResetPressed);
    on<FinalReorderSavePressed>(_onSavePressed);
    on<FinalReorderDialogConsumed>(_onDialogConsumed);
  }

  static FinalReorderState _buildInitial({
    required DailyOrderRow row,
    required int oldQtyInput,
    required int initialQtyInput,
    required int compareQtyInput,
    required String initialReasonInput,
  }) {
    final oldSafe = oldQtyInput < 0 ? 0 : oldQtyInput;
    final storeStock = _toInt(row.storeStock);
    final reorderQtyNum = _toInt(row.reorderQtyNum);
    final totalReorderToday = _toInt(row.totalReorderToday);

    final isNonFormulary =
        (row.branchFormulary ?? '').toString().trim().toUpperCase() == 'NON';

    final hasTma =
        (row.tmaQty ?? '').toString().trim().isNotEmpty &&
        (row.tmaQty ?? '0') != '0';

    final isLocked = storeStock <= 0;

    final onlyDecrease = reorderQtyNum > oldSafe;

    final initialQty = initialQtyInput;

    final clampedQty = _clampQty(
      v: initialQty,
      isLocked: isLocked,
      oldSafe: oldSafe,
      storeStock: storeStock,
      reorderQtyNum: reorderQtyNum,
      totalReorderToday: totalReorderToday,
    );

    return _recompute(
      qty: clampedQty,
      reason: initialReasonInput,
      oldSafe: oldSafe,
      storeStock: storeStock,
      reorderQtyNum: reorderQtyNum,
      compareQtyInput: compareQtyInput,
      totalReorderToday: totalReorderToday,
      isNonFormulary: isNonFormulary,
      hasTma: hasTma,
      isLocked: isLocked,
      onlyDecrease: onlyDecrease,
      dialog: null,
    );
  }

  void _onStarted(FinalReorderStarted e, Emitter<FinalReorderState> emit) {}

  void _onQtyTextChanged(
    FinalReorderQtyTextChanged e,
    Emitter<FinalReorderState> emit,
  ) {
    if (state.isNonFormulary) {
      emit(
        state.copyWith(
          dialog: const FinalReorderDialogPayload(
            title: 'NON Item',
            body: 'This item is NON formulary and cannot be edited.',
          ),
        ),
      );
      return;
    }

    final parsed = int.tryParse(e.text.trim()) ?? 0;
    final nextRaw = parsed.clamp(0, 1000000000);

    // 🔥 TMA → ممنوع decrease
    if (state.hasTma && nextRaw < state.oldQty) {
      emit(
        state.copyWith(
          dialog: const FinalReorderDialogPayload(
            title: 'TMA Restriction',
            body: 'You cannot decrease quantity for TMA items.',
          ),
        ),
      );
      return;
    }

    int next;
    FinalReorderDialogPayload? dialog;

    final isNoAdd = state.reorderQtyNum > state.oldQty;

    if (state.onlyDecrease || isNoAdd) {
      if (nextRaw > state.oldQty) {
        next = state.oldQty;

        dialog = const FinalReorderDialogPayload(
          title: 'Limited Stock',
          body:
              'Limited stock — you can only decrease this item. Adding is not allowed.',
        );
      } else {
        next = nextRaw;
      }
    } else {
      final clamped = _clampQty(
        v: nextRaw,
        isLocked: state.isLocked,
        oldSafe: state.oldQty,
        storeStock: state.storeStock,
        reorderQtyNum: state.reorderQtyNum,
        totalReorderToday: state.totalReorderToday,
      );

      next = clamped;

      if (clamped != nextRaw) {
        dialog = _dialogForExceeded(
          attempted: nextRaw,
          cap: _capForThisBranch(
            oldSafe: state.oldQty,
            storeStock: state.storeStock,
            reorderQtyNum: state.reorderQtyNum,
            totalReorderToday: state.totalReorderToday,
          ),
          onlyDecrease: state.onlyDecrease,
          storeStock: state.storeStock,
        );
      }
    }

    emit(
      _recompute(
        qty: next,
        reason: state.reason,
        oldSafe: state.oldQty,
        storeStock: state.storeStock,
        reorderQtyNum: state.reorderQtyNum,
        totalReorderToday: state.totalReorderToday,
        isNonFormulary: state.isNonFormulary,
        compareQtyInput: compareQtyInput,
        hasTma: state.hasTma,
        isLocked: state.isLocked,
        onlyDecrease: state.onlyDecrease,
        dialog: dialog,
      ),
    );
  }

  void _onInc(FinalReorderIncPressed e, Emitter<FinalReorderState> emit) {
    if (state.isNonFormulary) return;

    final cap = _capForThisBranch(
      oldSafe: state.oldQty,
      storeStock: state.storeStock,
      reorderQtyNum: state.reorderQtyNum,
      totalReorderToday: state.totalReorderToday,
    );

    final attempted = state.qty + 1;

    if (attempted > cap || state.isLocked) {
      emit(
        state.copyWith(
          dialog: _dialogForExceeded(
            attempted: attempted,
            cap: cap,
            onlyDecrease: state.onlyDecrease,
            storeStock: state.storeStock,
          ),
        ),
      );
      return;
    }

    emit(
      _recompute(
        qty: attempted,
        reason: state.reason,
        oldSafe: state.oldQty,
        compareQtyInput: compareQtyInput,
        storeStock: state.storeStock,
        reorderQtyNum: state.reorderQtyNum,
        totalReorderToday: state.totalReorderToday,
        isNonFormulary: state.isNonFormulary,
        hasTma: state.hasTma,
        isLocked: state.isLocked,
        onlyDecrease: state.onlyDecrease,
        dialog: state.dialog,
      ),
    );
  }

  void _onDec(FinalReorderDecPressed e, Emitter<FinalReorderState> emit) {
    if (state.isLocked) return;

    int next;

    if (state.hasTma) {
      next = (state.qty - 1).clamp(state.oldQty, 999999999);
    } else {
      final attempted = state.qty - 1;
      next = attempted < 0 ? 0 : attempted;
    }

    emit(
      _recompute(
        qty: next,
        reason: state.reason,
        oldSafe: state.oldQty,
        storeStock: state.storeStock,
        reorderQtyNum: state.reorderQtyNum,
        compareQtyInput: compareQtyInput,
        totalReorderToday: state.totalReorderToday,
        isNonFormulary: state.isNonFormulary,
        hasTma: state.hasTma,
        isLocked: state.isLocked,
        onlyDecrease: state.onlyDecrease,
        dialog: state.dialog,
      ),
    );
  }

  void _onReasonChanged(
    FinalReorderReasonChanged e,
    Emitter<FinalReorderState> emit,
  ) {
    emit(
      _recompute(
        qty: state.qty,
        reason: e.text,
        oldSafe: state.oldQty,
        storeStock: state.storeStock,
        compareQtyInput: compareQtyInput,
        reorderQtyNum: state.reorderQtyNum,
        totalReorderToday: state.totalReorderToday,
        isNonFormulary: state.isNonFormulary,
        hasTma: state.hasTma,
        isLocked: state.isLocked,
        onlyDecrease: state.onlyDecrease,
        dialog: state.dialog,
      ),
    );
  }

  void _onResetPressed(
    FinalReorderResetPressed e,
    Emitter<FinalReorderState> emit,
  ) {
    onReset();

    emit(
      _recompute(
        qty: state.oldQty,
        reason: state.reason,
        oldSafe: state.oldQty,
        storeStock: state.storeStock,
        reorderQtyNum: state.reorderQtyNum,
        compareQtyInput: compareQtyInput,
        totalReorderToday: state.totalReorderToday,
        isNonFormulary: state.isNonFormulary,
        hasTma: state.hasTma,
        isLocked: state.isLocked,
        onlyDecrease: state.onlyDecrease,
        dialog: state.dialog,
      ),
    );
  }

  Future<void> _onSavePressed(
    FinalReorderSavePressed e,
    Emitter<FinalReorderState> emit,
  ) async {
    if (!state.canSave) return;

    await onSave(state.qty, state.reason.trim());
  }

  void _onDialogConsumed(
    FinalReorderDialogConsumed e,
    Emitter<FinalReorderState> emit,
  ) {
    emit(state.copyWith(clearDialog: true));
  }

  // =========================
  // RECOMPUTE
  // =========================

  static FinalReorderState _recompute({
    required int qty,
    required String reason,
    required int oldSafe,
    required int compareQtyInput,
    required int storeStock,
    required int reorderQtyNum,
    required int totalReorderToday,
    required bool isNonFormulary,
    required bool hasTma,
    required bool isLocked,
    required bool onlyDecrease,
    required FinalReorderDialogPayload? dialog,
  }) {
    final cap = _capForThisBranch(
      oldSafe: oldSafe,
      storeStock: storeStock,
      reorderQtyNum: reorderQtyNum,
      totalReorderToday: totalReorderToday,
    );

    if (isNonFormulary) {
      return FinalReorderState(
        qty: oldSafe,
        reason: reason,
        oldQty: oldSafe,
        storeStock: storeStock,
        reorderQtyNum: reorderQtyNum,
        totalReorderToday: totalReorderToday,
        isNonFormulary: true,
        hasTma: hasTma,
        isLocked: true,
        onlyDecrease: onlyDecrease,
        capForThisBranch: oldSafe,
        canIncrease: false,
        canDecrease: false,
        hasChange: false,
        reasonOk: true,
        canSave: false,
        isLimitedStockLive: false,
        dialog: dialog,
      );
    }

    final canInc = !isLocked && qty < cap;
    final canDec = !isLocked && (hasTma ? qty > oldSafe : qty > 0);

    final hasChange = qty != compareQtyInput;
    final reasonOk = reason.trim().isNotEmpty;

    final canSave = !isLocked && hasChange && reasonOk && qty <= cap;

    final isLimitedStockLive =
        !isLocked && (reorderQtyNum > oldSafe || qty > cap);

    return FinalReorderState(
      qty: qty,
      reason: reason,
      oldQty: oldSafe,
      storeStock: storeStock,
      reorderQtyNum: reorderQtyNum,
      totalReorderToday: totalReorderToday,
      isNonFormulary: isNonFormulary,
      hasTma: hasTma,
      isLocked: isLocked,
      onlyDecrease: onlyDecrease,
      capForThisBranch: cap,
      canIncrease: canInc,
      canDecrease: canDec,
      hasChange: hasChange,
      reasonOk: reasonOk,
      canSave: canSave,
      isLimitedStockLive: isLimitedStockLive,
      dialog: dialog,
    );
  }

  // =========================
  // HELPERS
  // =========================

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    return int.tryParse(s.replaceAll(',', '')) ?? 0;
  }

  static int _capForThisBranch({
    required int oldSafe,
    required int storeStock,
    required int reorderQtyNum,
    required int totalReorderToday,
  }) {
    if (reorderQtyNum > oldSafe) {
      return oldSafe;
    }

    final availableStock = (storeStock - totalReorderToday).clamp(0, 999999999);
    final extra = (availableStock * 0.2).floor();

    return oldSafe + extra;
  }

  static int _clampQty({
    required int v,
    required bool isLocked,
    required int oldSafe,
    required int storeStock,
    required int reorderQtyNum,
    required int totalReorderToday,
  }) {
    if (isLocked) return oldSafe;

    final cap = _capForThisBranch(
      oldSafe: oldSafe,
      storeStock: storeStock,
      reorderQtyNum: reorderQtyNum,
      totalReorderToday: totalReorderToday,
    );

    if (v > cap) return cap;
    if (v < 0) return 0;

    return v;
  }

  static FinalReorderDialogPayload _dialogForExceeded({
    required int attempted,
    required int cap,
    required bool onlyDecrease,
    required int storeStock,
  }) {
    if (onlyDecrease) {
      return const FinalReorderDialogPayload(
        title: 'Limited Stock',
        body:
            'Limited stock — you can only decrease this item. Adding is not allowed.',
      );
    }

    if (attempted > storeStock) {
      return FinalReorderDialogPayload(
        title: 'Exceeded Store Stock',
        body:
            'You entered a quantity greater than store stock. Max allowed for this branch is $cap.',
      );
    }

    return FinalReorderDialogPayload(
      title: 'Exceeded Limit',
      body: 'Max allowed based on available stock is $cap.',
    );
  }
}
