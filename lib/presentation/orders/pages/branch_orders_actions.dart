import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
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
      barrierColor: Colors.black.withValues(alpha: 0.2),
      pageBuilder: (dialogContext, __, ___) {
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
      barrierColor: Colors.black.withValues(alpha: 0.2),
      pageBuilder: (dialogContext, __, ___) {
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

  static Future<bool?> openSubmitReviewDialog({
    required BuildContext context,
    required OrdersState state,
    required String zone,
  }) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return ReviewChangesDialog(
          rows: state.rows,
          edits: state.finalEdits,

          onEdit: (itemCode) {
            Navigator.of(context).pop(false);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              final row = state.rows.firstWhere((r) => r.itemCode == itemCode);

              openFinalSidePanel(context: context, state: state, row: row);
            });
          },

          onReset: (itemCode) {
            context.read<OrdersBloc>().add(OrdersResetFinalEdit(itemCode));
          },

          onClearAll: () {
            context.read<OrdersBloc>().add(const OrdersClearAllEdits());
          },

          // 🔥 NEW
          submitMode: true,

          // 🔥 NEW
          onConfirmSubmit: () {
            Navigator.of(context).pop(true);
          },
        );
      },
    );
  }

  static Future<void> openHistoryExportDialog(BuildContext context) async {
    final bloc = context.read<OrdersBloc>();

    // =====================
    // LOADING BEFORE DIALOG
    // =====================

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Colors.white,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryColor,
              ),
            ),
            SizedBox(width: 16),
            Text('Loading History...'),
          ],
        ),
      ),
    );

    final dates = await bloc.repo.fetchHistoryRunDates(
      branchName: bloc.state.branchName,
    );

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!context.mounted) return;

    String? downloadingDate;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),

              title: Row(
                children: [
                  const Icon(Icons.history, color: AppColors.primaryColor),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Export Order History'),

                        Text(
                          '${dates.length} Historical Orders',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
                height: 500,
                child: ListView.separated(
                  itemCount: dates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),

                  itemBuilder: (_, i) {
                    final runDate = dates[i];

                    final isLoading = downloadingDate == runDate;

                    return Card(
                      margin: EdgeInsets.only(top: 15),
                      color: AppColors.white,
                      elevation: 15,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: AppColors.primaryColor),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      shadowColor: AppColors.primaryColor,
                      child: ListTile(
                        leading: const Icon(Icons.calendar_month),

                        title: Text(
                          runDate,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),

                        trailing: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.download,
                                color: AppColors.secondaryColor,
                              ),

                        onTap: downloadingDate != null
                            ? null
                            : () async {
                                setState(() {
                                  downloadingDate = runDate;
                                });

                                try {
                                  final fileUrl = await bloc.repo
                                      .fetchHistoryFileUrl(
                                        branchName: bloc.state.branchName,
                                        runDate: runDate,
                                      );
                                  if (fileUrl == null) {
                                    throw Exception('History file not found');
                                  }

                                  html.window.open(fileUrl, '_blank');

                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } catch (e) {
                                  if (dialogContext.mounted) {
                                    ScaffoldMessenger.of(
                                      dialogContext,
                                    ).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }

                                  setState(() {
                                    downloadingDate = null;
                                  });
                                }
                              },
                      ),
                    );
                  },
                ),
              ),

              actions: [
                TextButton.icon(
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.secondaryColor,
                  ),
                  label: const Text(
                    'Close',
                    style: TextStyle(color: AppColors.secondaryColor),
                  ),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> openFinalSidePanel({
    required BuildContext context,
    required OrdersState state,
    required DailyOrderRow row,
  }) async {
    final oldQty =
        num.tryParse(row.finalReorderQtyStoreStockGt0.toString())?.toInt() ?? 0;

    final edit = state.finalEdits[row.itemCode];
    final alreadyEdited = state.finalEdits.containsKey(row.itemCode);

    final limitReached = state.finalEdits.length >= state.orderEditLimit;
    final initialQty = edit?.newQty ?? oldQty;
    final compareQty = edit?.newQty ?? oldQty;
    final initialReason = edit?.reason ?? '';
    if (!alreadyEdited && limitReached) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Edit Limit Reached'),
          content: Text(
            'Maximum edited products allowed: '
            '${state.orderEditLimit}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      return;
    }
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Edit Final Reorder',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      pageBuilder: (dialogContext, __, ___) {
        final navigator = Navigator.of(dialogContext);
        return Align(
          alignment: Alignment.centerRight,
          child: FinalReorderSidePanel(
            row: row,
            oldQty: oldQty,
            compareQty: compareQty,
            initialQty: initialQty,
            orderIncreaseLimit: state.orderIncreaseLimit,
            initialReason: initialReason,
            onClose: () => navigator.pop(),
            onSave: (newQty, reason) async {
              final bloc = context.read<OrdersBloc>();

              if (newQty == oldQty) {
                await bloc.repo.deleteFinalReorderDraft(
                  runDate: state.runDate,
                  branchName: state.branchName,
                  itemCode: row.itemCode,
                );
              } else {
                await bloc.repo.upsertFinalReorderDraft(
                  runDate: state.runDate,
                  branchName: state.branchName,
                  itemCode: row.itemCode,
                  itemName: row.itemName,
                  oldQty: oldQty,
                  newQty: newQty,
                  reason: reason,
                );
              }
              print('BEFORE POP');

              if (navigator.canPop()) {
                navigator.pop();
              }

              print('AFTER POP');

              await Future.delayed(const Duration(milliseconds: 100));

              bloc.add(
                OrdersApplyFinalEdit(
                  itemCode: row.itemCode,
                  oldQty: oldQty,
                  newQty: newQty,
                  reason: reason,
                ),
              );
            },
            onReset: () {
              context.read<OrdersBloc>().add(
                OrdersResetFinalEdit(row.itemCode),
              );
              navigator.pop();
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

    final bloc = context.read<OrdersBloc>();

    final latestState = bloc.state;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryColor,
              ),
            ),
            SizedBox(width: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
    final existingDraft = latestState.additionalEdits[itemCode];

    final isNewRequest = existingDraft == null;

    final currentCount = await bloc.repo.fetchAdditionalRequestsCount(
      runDate: latestState.runDate,
      branchName: latestState.branchName,
    );
    Navigator.of(context, rootNavigator: true).pop();
    final limitReached = currentCount >= latestState.additionalOrderLimit;

    if (isNewRequest && limitReached) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Additional Order Limit Reached'),
          content: Row(
            children: [
              Text('Maximum additional requests allowed: '),
              SizedBox(width: 10),
              Text(
                '${latestState.additionalOrderLimit}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  fontSize: 16.sp,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(color: AppColors.secondaryColor),
              ),
            ),
          ],
        ),
      );

      return;
    }
    final draft = existingDraft;

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
      barrierColor: Colors.black.withValues(alpha: 0.18),
      pageBuilder: (dialogContext, __, ___) {
        return Align(
          alignment: Alignment.centerRight,
          child: AdditionalRequestSidePanel(
            row: row,
            initialQty: draft?.requestQty,
            initialReason: draft?.reason ?? '',
            initialIsUrgent:
                latestState.additionalEdits[row.itemCode]?.isUrgent ?? false,

            onClose: () => Navigator.of(dialogContext).pop(),

            onSave: (qty, reason, isUrgent) async {
              final bloc = context.read<OrdersBloc>();

              // 🔥 SAVE ONLINE DRAFT
              await bloc.repo.upsertAdditionalRequestDraft(
                runDate: state.runDate,
                branchName: state.branchName,
                itemCode: row.itemCode,
                itemName: row.itemName,
                requestQty: qty,
                reason: reason,
                isUrgent: isUrgent,
              );

              // 🔥 SAVE LOCAL STATE
              bloc.add(
                OrdersApplyAdditionalRequest(
                  itemCode: itemCode,
                  itemName: row.itemName,
                  requestQty: qty,
                  reason: reason,
                  isUrgent: isUrgent,
                ),
              );

              Navigator.of(dialogContext).pop();
            },
            onRemove: () async {
              final bloc = context.read<OrdersBloc>();

              final draft = state.additionalEdits[itemCode];

              if (draft != null) {
                await bloc.repo.deleteAdditionalRequestDraft(id: draft.id);
              }

              bloc.add(OrdersRemoveAdditionalRequest(itemCode));

              Navigator.of(dialogContext).pop();
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
