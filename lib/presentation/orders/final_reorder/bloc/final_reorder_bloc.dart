import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/daily_order_row.dart';
import 'final_reorder_event.dart';
import 'final_reorder_state.dart';

class FinalReorderBloc extends Bloc<FinalReorderEvent, FinalReorderState> {
  final DailyOrderRow row;
  final int oldQtyInput;
  final int initialQtyInput;
  final String initialReasonInput;

  final void Function(int newQty, String reason) onSave;
  final void Function() onReset;

  FinalReorderBloc({
    required this.row,
    required this.oldQtyInput,
    required this.initialQtyInput,
    required this.initialReasonInput,
    required this.onSave,
    required this.onReset,
  }) : super(
         _buildInitial(
           row: row,
           oldQtyInput: oldQtyInput,
           initialQtyInput: initialQtyInput,
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
    required String initialReasonInput,
  }) {
    final oldSafe = oldQtyInput < 0 ? 0 : oldQtyInput;
    final storeStock = _toInt(row.storeStock);
    final reorderQtyNum = _toInt(row.reorderQtyNum);

    final isNonFormulary =
        (row.branchFormulary ?? '').toString().trim().toUpperCase() == 'NON';

    final isLocked = storeStock <= 0;
    final onlyDecrease = reorderQtyNum > oldSafe;

    final initialQty = (initialQtyInput < 0 ? 0 : initialQtyInput);
    final clampedQty = _clampQty(
      v: initialQty,
      isLocked: isLocked,
      oldSafe: oldSafe,
      storeStock: storeStock,
      onlyDecrease: onlyDecrease,
    );

    return _recompute(
      qty: clampedQty,
      reason: initialReasonInput,
      oldSafe: oldSafe,
      storeStock: storeStock,
      reorderQtyNum: reorderQtyNum,
      isNonFormulary: isNonFormulary,
      isLocked: isLocked,
      onlyDecrease: onlyDecrease,
      dialog: null,
    );
  }

  void _onStarted(FinalReorderStarted e, Emitter<FinalReorderState> emit) {
    // لو بدك أي logging
  }

  void _onQtyTextChanged(
    FinalReorderQtyTextChanged e,
    Emitter<FinalReorderState> emit,
  ) {
    final parsed = int.tryParse(e.text.trim()) ?? 0;
    final nextRaw = parsed.clamp(0, 1000000000);

    final next = _clampQty(
      v: nextRaw,
      isLocked: state.isLocked,
      oldSafe: state.oldQty,
      storeStock: state.storeStock,
      onlyDecrease: state.onlyDecrease,
    );

    if (next != nextRaw) {
      emit(
        state.copyWith(
          dialog: _dialogForExceeded(
            attempted: nextRaw,
            cap: _capForThisBranch(
              oldSafe: state.oldQty,
              storeStock: state.storeStock,
              onlyDecrease: state.onlyDecrease,
            ),
            onlyDecrease: state.onlyDecrease,
            storeStock: state.storeStock,
          ),
        ),
      );
    }

    emit(
      _recompute(
        qty: next,
        reason: state.reason,
        oldSafe: state.oldQty,
        storeStock: state.storeStock,
        reorderQtyNum: state.reorderQtyNum,
        isNonFormulary: state.isNonFormulary,
        isLocked: state.isLocked,
        onlyDecrease: state.onlyDecrease,
        dialog: state.dialog,
      ),
    );
  }

  void _onInc(FinalReorderIncPressed e, Emitter<FinalReorderState> emit) {
    final cap = _capForThisBranch(
      oldSafe: state.oldQty,
      storeStock: state.storeStock,
      onlyDecrease: state.onlyDecrease,
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
        storeStock: state.storeStock,
        reorderQtyNum: state.reorderQtyNum,
        isNonFormulary: state.isNonFormulary,
        isLocked: state.isLocked,
        onlyDecrease: state.onlyDecrease,
        dialog: state.dialog,
      ),
    );
  }

  void _onDec(FinalReorderDecPressed e, Emitter<FinalReorderState> emit) {
    if (state.isLocked) return;
    final attempted = state.qty - 1;
    final next = attempted < 0 ? 0 : attempted;

    emit(
      _recompute(
        qty: next,
        reason: state.reason,
        oldSafe: state.oldQty,
        storeStock: state.storeStock,
        reorderQtyNum: state.reorderQtyNum,
        isNonFormulary: state.isNonFormulary,
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
        reorderQtyNum: state.reorderQtyNum,
        isNonFormulary: state.isNonFormulary,
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

    // يرجع للـ auto (oldQty) ويمسح السبب (أو لا حسب رغبتك)
    emit(
      _recompute(
        qty: state.oldQty,
        reason: state.reason, // خلي السبب كما هو أو ''
        oldSafe: state.oldQty,
        storeStock: state.storeStock,
        reorderQtyNum: state.reorderQtyNum,
        isNonFormulary: state.isNonFormulary,
        isLocked: state.isLocked,
        onlyDecrease: state.onlyDecrease,
        dialog: state.dialog,
      ),
    );
  }

  void _onSavePressed(
    FinalReorderSavePressed e,
    Emitter<FinalReorderState> emit,
  ) {
    if (!state.canSave) return;
    onSave(state.qty, state.reason.trim());
  }

  void _onDialogConsumed(
    FinalReorderDialogConsumed e,
    Emitter<FinalReorderState> emit,
  ) {
    emit(state.copyWith(clearDialog: true));
  }

  // -------------------------
  // Pure helpers (no UI)
  // -------------------------

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
    required bool onlyDecrease,
  }) {
    if (onlyDecrease) return oldSafe;
    return math.max(oldSafe, storeStock);
  }

  static int _clampQty({
    required int v,
    required bool isLocked,
    required int oldSafe,
    required int storeStock,
    required bool onlyDecrease,
  }) {
    if (isLocked) return oldSafe;
    final cap = _capForThisBranch(
      oldSafe: oldSafe,
      storeStock: storeStock,
      onlyDecrease: onlyDecrease,
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
            'Reorder quantity is higher than the allowed auto quantity for this branch, so you cannot increase this item. You can only decrease.',
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
      body: 'Max allowed for this branch is $cap.',
    );
  }

  static FinalReorderState _recompute({
    required int qty,
    required String reason,
    required int oldSafe,
    required int storeStock,
    required int reorderQtyNum,
    required bool isNonFormulary,
    required bool isLocked,
    required bool onlyDecrease,
    required FinalReorderDialogPayload? dialog,
  }) {
    final cap = _capForThisBranch(
      oldSafe: oldSafe,
      storeStock: storeStock,
      onlyDecrease: onlyDecrease,
    );

    final canInc = !isLocked && qty < cap;
    final canDec = !isLocked && qty > 0;

    final hasChange = qty != oldSafe;
    final reasonOk = reason.trim().isNotEmpty;

    final canSave = !isLocked && hasChange && reasonOk && qty <= cap;

    final isLimitedStockLive = !isLocked && (onlyDecrease || qty > cap);

    return FinalReorderState(
      qty: qty,
      reason: reason,
      oldQty: oldSafe,
      storeStock: storeStock,
      reorderQtyNum: reorderQtyNum,
      isNonFormulary: isNonFormulary,
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
}
