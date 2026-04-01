import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/daily_order_row.dart';
import '../bloc/final_reorder_bloc.dart';
import '../bloc/final_reorder_event.dart';
import '../bloc/final_reorder_state.dart';
import 'branch_widgets.dart';
import 'limit_dialog.dart';

class FinalReorderSidePanel extends StatefulWidget {
  final DailyOrderRow row;

  final int oldQty;
  final int initialQty;
  final String initialReason;

  final VoidCallback onClose;
  final void Function(int newQty, String reason) onSave;
  final VoidCallback onReset;

  const FinalReorderSidePanel({
    super.key,
    required this.row,
    required this.oldQty,
    required this.initialQty,
    required this.initialReason,
    required this.onClose,
    required this.onSave,
    required this.onReset,
  });

  @override
  State<FinalReorderSidePanel> createState() => _FinalReorderSidePanelState();
}

class _FinalReorderSidePanelState extends State<FinalReorderSidePanel> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _reasonCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: widget.initialQty.toString());
    _reasonCtrl = TextEditingController(text: widget.initialReason);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => FinalReorderBloc(
        row: widget.row,
        oldQtyInput: widget.oldQty,
        initialQtyInput: widget.initialQty,
        initialReasonInput: widget.initialReason,
        onSave: widget.onSave,
        onReset: widget.onReset,
      )..add(const FinalReorderStarted()),
      child: BlocConsumer<FinalReorderBloc, FinalReorderState>(
        listenWhen: (p, n) =>
            p.dialog != n.dialog || p.qty != n.qty || p.reason != n.reason,
        listener: (context, s) async {
          final qtyText = s.qty.toString();
          if (_qtyCtrl.text != qtyText) {
            _qtyCtrl.value = TextEditingValue(
              text: qtyText,
              selection: TextSelection.collapsed(offset: qtyText.length),
            );
          }

          if (_reasonCtrl.text != s.reason) {
            final keep = _reasonCtrl.selection;
            _reasonCtrl.text = s.reason;
            _reasonCtrl.selection = keep;
          }

          // 2) Dialog side-effect
          if (s.dialog != null) {
            await showDialog<void>(
              context: context,
              barrierDismissible: true,
              builder: (_) =>
                  LimitDialog(title: s.dialog!.title, body: s.dialog!.body),
            );
            if (mounted) {
              context.read<FinalReorderBloc>().add(
                const FinalReorderDialogConsumed(),
              );
            }
          }
        },
        builder: (context, s) {
          final r = widget.row;

          return Material(
            color: Colors.transparent,
            child: Container(
              width: 460,
              height: MediaQuery.of(context).size.height,
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    FinalReorderHeader(
                      title: 'Edit Final Reorder',
                      subtitle: '${r.itemCode} • ${r.itemName}',
                      onClose: widget.onClose,
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (s.isLocked)
                              const AlertCard(
                                type: AlertType.blocked,
                                title: 'Editing Disabled',
                                body:
                                    'Store stock is 0, so editing final reorder is disabled for this item.',
                              ),

                            if (!s.isLocked && s.isNonFormulary)
                              const AlertCard(
                                type: AlertType.info,
                                title: 'NON Formulary',
                                body:
                                    'This item is NON-formulary. Please send it to the Zone Manager to convert it to ESSENTIAL to ensure refill when the product is sold.',
                              ),

                            if (!s.isLocked && s.isLimitedStockLive)
                              AlertCard(
                                type: AlertType.warning,
                                title: 'Limited Stock',
                                body: s.onlyDecrease
                                    ? 'Reorder quantity is higher than the allowed auto quantity for this branch, so you cannot increase this item. You can only decrease.'
                                    : 'Limited stock detected. You may not be able to increase this item. You can decrease if needed.',
                              ),

                            const SizedBox(height: 14),
                            const SectionTitle('Final Reorder'),
                            const SizedBox(height: 10),

                            TwoValuesRow(
                              leftTitle: 'Old QTY',
                              leftValue: s.oldQty.toString(),
                              rightTitle: 'Your Edit (New)',
                              rightValue: s.qty.toString(),
                            ),

                            const SizedBox(height: 12),

                            NumericField(
                              controller: _qtyCtrl,
                              enabled: !s.isLocked,
                              label: 'Enter new quantity',
                              helperText: s.isLocked
                                  ? 'Quantity editing is disabled.'
                                  : s.onlyDecrease
                                  ? 'You can only decrease from ${s.oldQty}.'
                                  : 'Numbers only. Max allowed: ${s.capForThisBranch}.',
                              onChanged: (v) => context
                                  .read<FinalReorderBloc>()
                                  .add(FinalReorderQtyTextChanged(v)),
                              onDec: () => context.read<FinalReorderBloc>().add(
                                const FinalReorderDecPressed(),
                              ),
                              onInc: () => context.read<FinalReorderBloc>().add(
                                const FinalReorderIncPressed(),
                              ),
                              canInc: s.canIncrease,
                              canDec: s.canDecrease,
                              maxAllowed: s.onlyDecrease
                                  ? s.oldQty
                                  : s.capForThisBranch,
                              // ✅ NEW
                            ),

                            /* const SizedBox(height: 10),

                            StepperRow(
                              value: s.qty,
                              onDec: () => context.read<FinalReorderBloc>().add(
                                const FinalReorderDecPressed(),
                              ),
                              onInc: () => context.read<FinalReorderBloc>().add(
                                const FinalReorderIncPressed(),
                              ),
                              canInc: s.canIncrease,
                              canDec: s.canDecrease,
                              disabled: s.isLocked,
                            ),*/
                            const SizedBox(height: 10),

                            DiffChip(
                              oldQty: s.oldQty,
                              newQty: int.tryParse(_qtyCtrl.text) ?? 0,
                            ),

                            const SizedBox(height: 18),

                            const SectionTitle('Reason (Required)'),
                            const SizedBox(height: 10),

                            ReasonField(
                              controller: _reasonCtrl,
                              enabled: !s.isLocked,
                              showError:
                                  !s.reasonOk && s.hasChange && !s.isLocked,
                              onChanged: (v) => context
                                  .read<FinalReorderBloc>()
                                  .add(FinalReorderReasonChanged(v)), // ✅ NEW
                            ),

                            const SizedBox(height: 18),

                            MiniStats(
                              row: r,
                              storeStock: s.storeStock,
                              minReOrder: r.reorderPointMin!.toInt(),
                              onlyDecrease: s.onlyDecrease,
                              reorderQtyNum: s.reorderQtyNum,
                              maxReorder: r.reorderMax!.toInt(),
                            ),

                            const SizedBox(height: 18),
                            const Divider(),
                            const SizedBox(height: 10),

                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: widget.onClose,
                                    child: const Text(
                                      'Close',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.secondaryColor,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: s.canSave
                                        ? () => context
                                              .read<FinalReorderBloc>()
                                              .add(
                                                const FinalReorderSavePressed(),
                                              )
                                        : null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.primaryColor,
                                    ),
                                    icon: const Icon(Icons.save),
                                    label: const Text('Save'),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
