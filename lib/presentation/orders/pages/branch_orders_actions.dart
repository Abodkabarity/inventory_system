import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/daily_order_row.dart';
import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';
import '../final_reorder/widgets/final_reorder_side_panel.dart';
import '../widgets/additional_request_side_panel.dart';
import '../widgets/additional_requests_tracking_dialog.dart';
import '../widgets/max_side_panel.dart';
import '../widgets/mismatch_side_panel.dart';
import '../widgets/review_changes_dialog.dart';

class BranchOrdersActions {
  static Future<void> openTrackingDialog(BuildContext context) async {
    final bloc = context.read<OrdersBloc>();
    bloc.add(const OrdersLoadAdditionalTracking());

    await showDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: true,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: const AdditionalTrackingDialog(),
      ),
    );
  }

  static Future<void> openMismatchPanel(BuildContext context) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Mismatch',
      barrierColor: Colors.black.withOpacity(0.2),
      pageBuilder: (_, __, ___) {
        return Align(
          alignment: Alignment.centerRight,
          child: BlocProvider.value(
            value: context.read<OrdersBloc>(),
            child: const Material(
              color: Colors.transparent,
              child: MismatchSidePanel(),
            ),
          ),
        );
      },
    );
  }

  static Future<void> openMaxPanel(BuildContext context) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Max',
      barrierColor: Colors.black.withOpacity(0.2),
      pageBuilder: (_, __, ___) {
        return Align(
          alignment: Alignment.centerRight,
          child: BlocProvider.value(
            value: context.read<OrdersBloc>(),
            child: const Material(
              color: Colors.transparent,
              child: MaxSidePanel(),
            ),
          ),
        );
      },
    );
  }

  static Future<void> openReviewDialog({
    required BuildContext context,
    required OrdersState state,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ReviewChangesDialog(
        rows: state.rows,
        edits: state.finalEdits,
        onEdit: (itemCode) {
          Navigator.of(context).pop();
          final row = state.rows.firstWhere((r) => r.itemCode == itemCode);
          openFinalSidePanel(context: context, state: state, row: row);
        },
        onReset: (itemCode) {
          context.read<OrdersBloc>().add(OrdersResetFinalEdit(itemCode));
        },
        onClearAll: () {
          context.read<OrdersBloc>().add(const OrdersClearAllEdits());
        },
      ),
    );
  }

  static Future<void> openFinalSidePanel({
    required BuildContext context,
    required OrdersState state,
    required DailyOrderRow row,
  }) async {
    final oldQty = _extractNumeric(row.finalReorderQtyStoreStockGt0).round();

    final edit = state.finalEdits[row.itemCode];
    final initialQty = edit?.newQty ?? oldQty;
    final initialReason = edit?.reason ?? '';

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Edit Final Reorder',
      barrierColor: Colors.black.withOpacity(0.18),
      pageBuilder: (_, __, ___) {
        return Align(
          alignment: Alignment.centerRight,
          child: FinalReorderSidePanel(
            row: row,
            oldQty: oldQty,
            initialQty: initialQty,
            initialReason: initialReason,
            onClose: () => Navigator.of(context).pop(),
            onSave: (newQty, reason) {
              context.read<OrdersBloc>().add(
                OrdersApplyFinalEdit(
                  itemCode: row.itemCode,
                  oldQty: oldQty,
                  newQty: newQty,
                  reason: reason,
                ),
              );
              Navigator.of(context).pop();
            },
            onReset: () {
              context.read<OrdersBloc>().add(
                OrdersResetFinalEdit(row.itemCode),
              );
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }

  static Future<void> openAdditionalSidePanel({
    required BuildContext context,
    required OrdersState state,
    required DailyOrderRow row,
  }) async {
    final itemCode = row.itemCode;
    final draft = state.additionalEdits[itemCode];

    final rawHistory =
        state.sentAdditionalHistoryByItemCode[itemCode] ?? const [];
    final sentHistory = rawHistory.map((r) {
      final v = r['request_qty'];
      final qty = (v is num) ? v : (num.tryParse((v ?? '').toString()) ?? 0);
      final reason = (r['reason'] ?? '').toString();
      final createdAtStr = (r['created_at'] ?? '').toString();
      final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();

      return SentAdditionalRequest(
        qty: qty,
        reason: reason,
        createdAt: createdAt,
      );
    }).toList();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Additional Request',
      barrierColor: Colors.black.withOpacity(0.18),
      pageBuilder: (_, __, ___) {
        return Align(
          alignment: Alignment.centerRight,
          child: AdditionalRequestSidePanel(
            row: row,
            initialQty: draft?.requestQty,
            initialReason: draft?.reason ?? '',
            onClose: () => Navigator.of(context).pop(),
            onSave: (qty, reason) {
              context.read<OrdersBloc>().add(
                OrdersApplyAdditionalRequest(
                  itemCode: itemCode,
                  itemName: row.itemName,
                  requestQty: qty,
                  reason: reason,
                ),
              );
              Navigator.of(context).pop();
            },
            onRemove: () {
              context.read<OrdersBloc>().add(
                OrdersRemoveAdditionalRequest(itemCode),
              );
              Navigator.of(context).pop();
            },
            sentHistory: sentHistory,
          ),
        );
      },
    );
  }

  static num _extractNumeric(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 0;

    final direct = num.tryParse(s.replaceAll(',', ''));
    if (direct != null) return direct;

    final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    if (m == null) return 0;
    return num.tryParse(m.group(0) ?? '') ?? 0;
  }
}
