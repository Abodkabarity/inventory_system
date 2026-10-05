import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../../core/helper/final_reorder_limit_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/operational_date_helper.dart';
import '../../../core/utils/uae_date_time_formatter.dart';
import '../../../domain/entities/branch_allocation_task.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../../insurance_assistant/page/insurance_assistant_page.dart';
import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';
import '../final_reorder/widgets/limit_dialog.dart';
import '../widgets/branch_allocation_dialog.dart';
import '../widgets/branch_stock_check_page.dart';
import '../widgets/branch_zone_cubit.dart';
import '../widgets/items_to_order_dialog.dart';
import '../widgets/insurance_assistant_zone_access.dart';
import '../widgets/low_demand_order_suggestions_dialog.dart';
import '../widgets/max_allowed_dialog.dart';
import '../widgets/orders_grid_controller.dart';
import '../widgets/orders_table.dart';
import '../widgets/orders_toolbar.dart';
import '../widgets/pending_items_to_order_dialog.dart';
import 'branch_orders_actions.dart';
import 'branch_order_guide_page.dart';
import 'branch_orders_selectors.dart';
import 'branch_widgets/columns_panel.dart';

class BranchOrdersScreen extends StatefulWidget {
  const BranchOrdersScreen({super.key});

  @override
  State<BranchOrdersScreen> createState() => _BranchOrdersScreenState();
}

class _BranchOrdersScreenState extends State<BranchOrdersScreen> {
  late final OrdersGridController _grid;
  RealtimeChannel? _jobChannel;
  Timer? _operationalTimer;
  Timer? _pendingWorkTimer;

  bool _newDayDialogVisible = false;
  bool _ordersDrawerOpen = false;
  bool _showAllocationPage = false;
  bool _showStockCheckPage = false;
  bool _showInsuranceAssistantPage = false;
  bool _showGuidePage = false;
  bool _stockCheckLoading = false;
  String _stockCheckBranchName = '';
  _StockCheckPendingInfo _stockCheckInfo = _StockCheckPendingInfo.empty();

  bool get _showMaxZeroKpiCard => false;

  int _rowInt(num? value) => value?.toInt() ?? 0;

  int _rowOrderStep(DailyOrderRow row) {
    final parsed = num.tryParse((row.minOrderUnit ?? '').trim());
    if (parsed == null || parsed <= 1) return 1;
    return parsed.round();
  }

  bool _hasBlankFinalReorder(DailyOrderRow row) {
    final value = row.finalReorderQtyStoreStockGt0.trim().toLowerCase();
    return value.isEmpty || value == '-' || value == 'null';
  }

  List<LowDemandOrderSuggestion> _buildLowDemandSuggestions(OrdersState state) {
    final suggestions = <LowDemandOrderSuggestion>[];
    final seen = <String>{};

    for (final row in state.rows) {
      if (seen.contains(row.itemCode)) continue;
      if (!_hasBlankFinalReorder(row)) continue;
      if (state.finalEdits.containsKey(row.itemCode)) continue;
      if (row.demandFor30Days <= 0 || row.demandFor30Days > 6) continue;
      if (row.branchStock >= row.demandFor30Days) continue;
      if (_rowInt(row.storeStock) <= 0) continue;
      if ((row.branchFormulary ?? '').trim().toUpperCase() == 'NON') continue;

      final step = _rowOrderStep(row);
      final cap = FinalReorderLimitHelper.capForThisBranch(
        oldSafe: 0,
        storeStock: _rowInt(row.storeStock),
        reorderQtyNum: _rowInt(row.reorderQtyNum),
        totalReorderToday: row.totalReorderToday ?? 0,
        orderIncreaseLimit: state.orderIncreaseLimit,
        orderStep: step,
      );
      if (cap < step) continue;

      seen.add(row.itemCode);
      suggestions.add(
        LowDemandOrderSuggestion(
          itemCode: row.itemCode,
          itemName: row.itemName,
          demand: row.demandFor30Days,
          branchStock: row.branchStock,
          maxQty: cap,
          step: step,
        ),
      );
    }

    suggestions.sort((a, b) => a.itemName.compareTo(b.itemName));
    return suggestions;
  }

  Future<void> _openLowDemandSuggestions(OrdersBloc bloc) async {
    final items = _buildLowDemandSuggestions(bloc.state);
    if (items.isEmpty || !mounted) return;

    await LowDemandOrderSuggestionsDialog.show(
      context: context,
      items: items,
      onAdd: (item, quantity) async {
        try {
          await bloc.repo.upsertFinalReorderDraft(
            runDate: bloc.state.runDate,
            branchName: bloc.state.branchName,
            itemCode: item.itemCode,
            itemName: item.itemName,
            oldQty: 0,
            newQty: quantity,
            reason: 'Low Demand Review',
            applyMaxAdj: false,
          );
          bloc.add(
            OrdersApplyFinalEdit(
              itemCode: item.itemCode,
              oldQty: 0,
              newQty: quantity,
              reason: 'Low Demand Review',
              applyMaxAdj: false,
            ),
          );
          return true;
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not add ${item.itemCode}. Please try again.',
                ),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
          return false;
        }
      },
    );
  }

  String? _lastDialogDate;
  @override
  void initState() {
    super.initState();

    _grid = OrdersGridController();

    _startOperationalWatcher();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<OrdersBloc>().state;
      context.read<OrdersBloc>().add(const OrdersLoadBranchAllocationTasks());
      _loadPendingStockChecks(state.branchName);
    });
    _pendingWorkTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final branchName = context.read<OrdersBloc>().state.branchName;
      _loadPendingStockChecks(branchName, showLoading: false);
      setState(() {});
    });
  }

  Future<void> _loadPendingStockChecks(
    String branchName, {
    bool showLoading = true,
  }) async {
    if (branchName.trim().isEmpty) return;
    if (showLoading) {
      setState(() {
        _stockCheckLoading = true;
        _stockCheckBranchName = branchName;
      });
    } else {
      _stockCheckBranchName = branchName;
    }
    try {
      final rows = await Supabase.instance.client
          .from('stock_check_tasks')
          .select('id,batch_id,title,source,sent_at,expires_at')
          .eq('branch_name', branchName)
          .eq('status', 'pending')
          .order('sent_at');
      final info = _StockCheckPendingInfo.fromRows(
        List<Map<String, dynamic>>.from(rows),
      );
      if (!mounted) return;
      setState(() {
        _stockCheckInfo = info;
        _stockCheckLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stockCheckInfo = _StockCheckPendingInfo.empty();
        _stockCheckLoading = false;
      });
    }
  }

  void _startOperationalWatcher() {
    _operationalTimer?.cancel();

    _operationalTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted) return;

      final now = OperationalDateHelper.nowUae;

      if (now.hour < 21) {
        return;
      }

      final nextOperationalDate = OperationalDateHelper.operationalDate;
      final currentRunDate = context.read<OrdersBloc>().state.runDate;

      // Already on latest operational order
      if (currentRunDate == nextOperationalDate) {
        // prevent dialog showing repeatedly
        _lastDialogDate = nextOperationalDate;

        return;
      }
      if (_lastDialogDate == nextOperationalDate) {
        return;
      }

      _lastDialogDate = nextOperationalDate;

      if (_newDayDialogVisible) {
        return;
      }

      _newDayDialogVisible = true;

      if (!mounted) return;

      await _showNewOrderDialog(nextOperationalDate);

      _newDayDialogVisible = false;
    });
  }

  void _openBranchAllocationPage(BuildContext context) {
    setState(() {
      _showAllocationPage = true;
      _showStockCheckPage = false;
      _showInsuranceAssistantPage = false;
      _showGuidePage = false;
      _ordersDrawerOpen = false;
    });
    context.read<OrdersBloc>().add(const OrdersLoadBranchAllocationTasks());
  }

  void _openBranchStockCheckPage() {
    setState(() {
      _showStockCheckPage = true;
      _showAllocationPage = false;
      _showInsuranceAssistantPage = false;
      _showGuidePage = false;
      _ordersDrawerOpen = false;
    });
  }

  void _openInsuranceAssistantPage() {
    final zone = context.read<BranchZoneCubit>().state.zone;
    if (!InsuranceAssistantZoneAccess.isEnabled(zone)) return;
    setState(() {
      _showInsuranceAssistantPage = true;
      _showGuidePage = false;
      _showStockCheckPage = false;
      _showAllocationPage = false;
      _ordersDrawerOpen = false;
    });
  }

  void _openOrderPage() {
    final branchName = context.read<OrdersBloc>().state.branchName;
    setState(() {
      _showAllocationPage = false;
      _showStockCheckPage = false;
      _showInsuranceAssistantPage = false;
      _showGuidePage = false;
      _ordersDrawerOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrdersBloc>().add(const OrdersLoadBranchAllocationTasks());
      _loadPendingStockChecks(branchName, showLoading: false);
    });
  }

  void _openGuidePage() {
    setState(() {
      _showGuidePage = true;
      _showAllocationPage = false;
      _showStockCheckPage = false;
      _showInsuranceAssistantPage = false;
      _ordersDrawerOpen = false;
    });
  }

  Future<void> _showNewOrderDialog(String operationalDate) async {
    final bloc = context.read<OrdersBloc>();

    bool loading = false;

    String? errorMessage;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return PopScope(
              canPop: false,
              child: Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  width: 420,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .18),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),

                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // =========================
                      // ICON
                      // =========================
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFF97316),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFF97316),
                          size: 52,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // =========================
                      // TITLE
                      // =========================
                      const Text(
                        'NEW ORDER AVAILABLE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                          letterSpacing: .6,
                        ),
                      ),

                      const SizedBox(height: 18),

                      const Text(
                        'A new operational order is available.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF374151),
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 14),

                      const Text(
                        'PLEASE REFRESH THE PAGE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.red,
                          letterSpacing: 1.3,
                        ),
                      ),

                      // =========================
                      // ERROR MESSAGE
                      // =========================
                      if (errorMessage != null) ...[
                        const SizedBox(height: 22),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFFDA4AF),
                              width: 1.4,
                            ),
                          ),

                          child: Row(
                            children: [
                              const Icon(
                                Icons.schedule,
                                color: Color(0xFFDC2626),
                                size: 28,
                              ),

                              const SizedBox(width: 14),

                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFB91C1C),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // =========================
                      // LOADING
                      // =========================
                      if (loading) ...[
                        const SizedBox(height: 28),

                        const CircularProgressIndicator(
                          color: AppColors.primaryColor,
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          'Checking new order...',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],

                      const SizedBox(height: 30),

                      // =========================
                      // BUTTON
                      // =========================
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text(
                            'REFRESH ORDER',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .5,
                            ),
                          ),

                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),

                          onPressed: loading
                              ? null
                              : () async {
                                  setState(() {
                                    loading = true;
                                    errorMessage = null;
                                  });

                                  final ready = await bloc.repo
                                      .isOperationalOrderReady(
                                        runDate: operationalDate,
                                      );

                                  if (!mounted) return;

                                  // =========================
                                  // READY
                                  // =========================

                                  if (ready) {
                                    Navigator.of(dialogContext).pop();

                                    bloc.add(
                                      const OrdersRefreshOperationalDate(),
                                    );
                                    bloc.add(const OrdersCheckAutoLoad());

                                    return;
                                  }

                                  // =========================
                                  // STILL CALCULATING
                                  // =========================

                                  setState(() {
                                    loading = false;

                                    errorMessage =
                                        'The new order is still calculating.\nPlease wait a few minutes and try again.';
                                  });
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _jobChannel?.unsubscribe();
    _operationalTimer?.cancel();
    _pendingWorkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('UAE NOW: ${OperationalDateHelper.nowUae}');
    return BlocBuilder<OrdersBloc, OrdersState>(
      builder: (context, s) {
        final isBusy = s.isBusy;
        final insuranceAssistantEnabled =
            InsuranceAssistantZoneAccess.isEnabled(
              context.watch<BranchZoneCubit>().state.zone,
            );
        final showInsuranceAssistantPage =
            insuranceAssistantEnabled && _showInsuranceAssistantPage;

        final visibleStats = BranchOrdersSelectors.calcStats(
          s.viewRows,
          maxAdjZeroItemCodes: s.maxAdjZeroItemCodes,
        );
        final categories = BranchOrdersSelectors.extractCategories(s.rows);
        final useLimitedStockMode =
            !s.isSubmitted &&
            !OperationalDateHelper.isMissingWindowForBranch(
              startHour: s.submitStartHour,
              endHour: s.submitEndHour,
            );
        final showFullOrderColumns =
            s.isOrderDay || s.isMissingOrder || s.isSubmitted;
        final showAdditionalRowActions =
            s.isSubmitted ||
            s.isMissingOrder ||
            !s.isOrderDay ||
            !OperationalDateHelper.canSubmitForBranch(
              startHour: s.submitStartHour,
              endHour: s.submitEndHour,
            );
        final canEditFinalReorder = !s.isSubmitted && s.isOrderDay;
        final orderedColumns = showFullOrderColumns
            ? BranchOrdersSelectors.orderedVisibleColumns(s)
            : ['item_code', 'item_name', 'branch_stock', 'store_stock'];

        final draftAddCount = s.additionalCount;

        final usedAdditional = s.usedAdditionalOrders;

        final additionalLimit = s.additionalOrderLimit.toInt();
        final hasAllocationNotice =
            s.hasPendingAllocation || s.incomingAllocationTasks.isNotEmpty;
        final allocationInfo = _AllocationPendingInfo.fromTasks([
          ...s.outgoingAllocationTasks.where((task) => task.isSenderPending),
          ...s.incomingAllocationTasks,
        ]);
        if (_stockCheckBranchName != s.branchName && !_stockCheckLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadPendingStockChecks(s.branchName);
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF6F7FB),
          endDrawer: const ColumnsPanel(),
          body: Stack(
            children: [
              SafeArea(
                child: showInsuranceAssistantPage
                    ? InsuranceAssistantPage(
                        branchName: s.branchName,
                        onBack: _openOrderPage,
                      )
                    : _showGuidePage
                    ? BranchOrderGuidePage(onBack: _openOrderPage)
                    : _showStockCheckPage
                    ? BranchStockCheckPage(
                        branchName: s.branchName,
                        onBack: _openOrderPage,
                      )
                    : _showAllocationPage
                    ? BranchAllocationPage(onBack: _openOrderPage)
                    : Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            BlocBuilder<BranchZoneCubit, BranchZoneState>(
                              builder: (context, zs) {
                                return _TopHeader(
                                  title: s.branchName,
                                  subtitle: 'Orders - ${s.runDate}',
                                  right: Row(
                                    children: [
                                      FilledButton.icon(
                                        icon: const Icon(Icons.save),

                                        label: const Text('Save Setting'),

                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),

                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              backgroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),

                                              title: const Row(
                                                children: [
                                                  Icon(
                                                    Icons.save_outlined,
                                                    color:
                                                        AppColors.primaryColor,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Save Layout'),
                                                ],
                                              ),

                                              content: const Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'This will save your personal table layout.',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),

                                                  SizedBox(height: 12),

                                                  Text(
                                                    'Check Visible / Hidden Columns',
                                                  ),

                                                  SizedBox(height: 4),

                                                  Text(
                                                    'Check Column Arrangement',
                                                  ),

                                                  SizedBox(height: 4),

                                                  Text('Check Column Widths'),

                                                  SizedBox(height: 12),

                                                  Text(
                                                    'The layout will be restored automatically after refresh or login.',
                                                  ),
                                                ],
                                              ),

                                              actions: [
                                                TextButton(
                                                  onPressed: () {
                                                    Navigator.pop(
                                                      context,
                                                      false,
                                                    );
                                                  },
                                                  child: const Text(
                                                    'Cancel',
                                                    style: TextStyle(
                                                      color: AppColors
                                                          .secondaryColor,
                                                    ),
                                                  ),
                                                ),

                                                OutlinedButton.icon(
                                                  icon: const Icon(
                                                    Icons.restart_alt,
                                                    color: Colors.red,
                                                  ),

                                                  label: const Text(
                                                    'Reset',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),

                                                  style:
                                                      OutlinedButton.styleFrom(
                                                        side: const BorderSide(
                                                          color: Colors.red,
                                                        ),
                                                      ),

                                                  onPressed: () async {
                                                    final resetConfirm = await showDialog<bool>(
                                                      context: context,
                                                      builder: (_) => AlertDialog(
                                                        backgroundColor:
                                                            Colors.white,

                                                        title: const Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .warning_amber_rounded,
                                                              color: Colors.red,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text(
                                                              'Reset Layout',
                                                            ),
                                                          ],
                                                        ),

                                                        content: const Text(
                                                          'This will permanently remove all saved layout settings for this branch and restore the default table layout.\n\nDo you want to continue?',
                                                        ),

                                                        actions: [
                                                          TextButton(
                                                            onPressed: () {
                                                              Navigator.pop(
                                                                context,
                                                                false,
                                                              );
                                                            },
                                                            child: const Text(
                                                              'Cancel',
                                                            ),
                                                          ),

                                                          FilledButton.icon(
                                                            icon: const Icon(
                                                              Icons
                                                                  .delete_forever,
                                                            ),
                                                            label: const Text(
                                                              'Reset',
                                                            ),
                                                            style:
                                                                FilledButton.styleFrom(
                                                                  backgroundColor:
                                                                      Colors
                                                                          .red,
                                                                ),
                                                            onPressed: () {
                                                              Navigator.pop(
                                                                context,
                                                                true,
                                                              );
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                    );

                                                    if (resetConfirm != true)
                                                      return;

                                                    if (!context.mounted)
                                                      return;

                                                    context.read<OrdersBloc>().add(
                                                      const OrdersDeleteUiSettings(),
                                                    );

                                                    Navigator.pop(
                                                      context,
                                                      false,
                                                    );

                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Layout Reset Successfully',
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),

                                                FilledButton.icon(
                                                  icon: const Icon(Icons.save),
                                                  label: const Text('Confirm'),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor:
                                                        AppColors.primaryColor,
                                                  ),
                                                  onPressed: () {
                                                    Navigator.pop(
                                                      context,
                                                      true,
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirm != true) return;

                                          context.read<OrdersBloc>().add(
                                            const OrdersSaveUiSettings(),
                                          );

                                          if (!context.mounted) return;

                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Layout Saved Successfully',
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 10),
                                      FilledButton.icon(
                                        onPressed: () {
                                          context.read<OrdersBloc>().add(
                                            const OrdersExportPressed(),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.download,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Export',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.blueGrey,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      FilledButton.icon(
                                        onPressed: () {
                                          BranchOrdersActions.openNonReceivedExportDialog(
                                            context,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.inventory_2_outlined,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Non Recived',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.teal,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      FilledButton.icon(
                                        onPressed: () {
                                          BranchOrdersActions.openHistoryExportDialog(
                                            context,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.download,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Order History',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.deepPurple,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      _StatusChip(
                                        isSubmitted: s.isSubmitted,
                                        isOrderDay: s.isOrderDay,
                                        runDate: s.runDate,
                                        nextOrderDate: s.nextOrderDate,
                                        nextPreparationAt: s.nextPreparationAt,
                                        nextPreparationDeadlineAt:
                                            s.nextPreparationDeadlineAt,
                                        isMissingOrder:
                                            s.isMissingOrder && !s.isSubmitted,
                                      ),

                                      const SizedBox(width: 10),

                                      _EditLimitChip(
                                        used: s.increasedEditsCount,
                                        limit: s.orderEditLimit,
                                      ),

                                      const SizedBox(width: 10),

                                      _ZoneChip(zone: zs.zone),

                                      const SizedBox(width: 10),
                                    ],
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 5),

                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (s.showCreate)
                                      SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height *
                                            .7,
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.inventory_2_outlined,
                                                size: 90,
                                                color: AppColors.primaryColor,
                                              ),

                                              const SizedBox(height: 20),

                                              const Text(
                                                'Daily Order',
                                                style: TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),

                                              const SizedBox(height: 10),

                                              const Text(
                                                'Click Create Order to load today order',
                                              ),

                                              const SizedBox(height: 25),

                                              FilledButton.icon(
                                                icon: const Icon(Icons.create),

                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.primaryColor,
                                                  minimumSize: Size(
                                                    250.w,
                                                    45.h,
                                                  ),
                                                  elevation: 20,
                                                  shadowColor:
                                                      AppColors.secondaryColor,
                                                ),
                                                label: Text(
                                                  'Create Order',
                                                  style: TextStyle(
                                                    fontSize: 18.sp,
                                                  ),
                                                ),
                                                onPressed: () {
                                                  context
                                                      .read<OrdersBloc>()
                                                      .add(
                                                        const OrdersLoadAll(),
                                                      );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else if (s.status == OrdersStatus.loading &&
                                        s.rows.isEmpty)
                                      SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height *
                                            0.7.h,
                                        child: Center(
                                          child: Container(
                                            width: 520,
                                            padding: const EdgeInsets.all(22),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                              border: Border.all(
                                                color: const Color(0xFFE6E8F0),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.05),
                                                  blurRadius: 30,
                                                  offset: const Offset(0, 16),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const CircularProgressIndicator(
                                                  color: AppColors.primaryColor,
                                                ),

                                                const SizedBox(height: 20),

                                                const Text(
                                                  'Generating Order',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),

                                                const SizedBox(height: 10),

                                                Text(
                                                  s.progressMessage ??
                                                      'Please wait...',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    else ...[
                                      if (s.status == OrdersStatus.generating ||
                                          s.status == OrdersStatus.loading)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: _ProgressStrip(
                                            progress: s.progress,
                                            message:
                                                s.progressMessage ??
                                                'Working...',
                                          ),
                                        ),

                                      if (s.status == OrdersStatus.failure &&
                                          s.error != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: Text(
                                            s.error!,
                                            style: const TextStyle(
                                              color: Colors.red,
                                            ),
                                          ),
                                        ),

                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final showMaxZeroKpiCard =
                                              _showMaxZeroKpiCard;
                                          final hasUrgentWork =
                                              hasAllocationNotice ||
                                              _stockCheckInfo.hasPending;
                                          final cardCount =
                                              3 +
                                              (hasUrgentWork ? 1 : 0) +
                                              (showMaxZeroKpiCard ? 1 : 0);
                                          final cardWidth =
                                              ((constraints.maxWidth -
                                                          ((cardCount - 1) *
                                                              18)) /
                                                      cardCount)
                                                  .clamp(250.0, 360.0)
                                                  .toDouble();

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              left: 132,
                                            ),
                                            child: Row(
                                              spacing: 18,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceEvenly,
                                              children: [
                                                SizedBox(
                                                  width: cardWidth,
                                                  child: _KpiCard(
                                                    title: 'Visible Products',
                                                    value: visibleStats
                                                        .totalProducts
                                                        .toString(),
                                                    subtitle:
                                                        s.viewRows.length ==
                                                            s.rows.length
                                                        ? 'All APG Items'
                                                        : 'Filtered items',
                                                    icon:
                                                        Icons.list_alt_outlined,
                                                    isSelected: false,
                                                  ),
                                                ),

                                                SizedBox(
                                                  width: cardWidth,
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      context.read<OrdersBloc>().add(
                                                        OrdersNumericFinalOnlyToggled(
                                                          !s.numericFinalOnly,
                                                        ),
                                                      );
                                                    },
                                                    child: _KpiCard(
                                                      title: 'Items in Order',
                                                      value: visibleStats
                                                          .finalReorderCount
                                                          .round()
                                                          .toString(),
                                                      subtitle: '',
                                                      icon: Icons
                                                          .inventory_2_outlined,
                                                      isSelected:
                                                          s.numericFinalOnly,
                                                    ),
                                                  ),
                                                ),

                                                if (hasUrgentWork)
                                                  SizedBox(
                                                    width: cardWidth,
                                                    child: _BranchUrgentWorkBanner(
                                                      hasAllocation:
                                                          hasAllocationNotice,
                                                      allocationCount:
                                                          s.pendingOutgoingAllocationCount +
                                                          s
                                                              .incomingAllocationTasks
                                                              .length,
                                                      overdueAllocationCount:
                                                          allocationInfo
                                                              .overdueCount,
                                                      hasStockCheck:
                                                          _stockCheckInfo
                                                              .hasPending,
                                                      stockCheckCount:
                                                          _stockCheckInfo
                                                              .pendingCount,
                                                      overdueStockCheckCount:
                                                          _stockCheckInfo
                                                              .overdueCount,
                                                      stockCheckLoading:
                                                          _stockCheckLoading,
                                                      onTap: () {
                                                        if (hasAllocationNotice &&
                                                            _stockCheckInfo
                                                                .hasPending) {
                                                          setState(() {
                                                            _ordersDrawerOpen =
                                                                true;
                                                          });
                                                          return;
                                                        }
                                                        if (_stockCheckInfo
                                                            .hasPending) {
                                                          _openBranchStockCheckPage();
                                                          return;
                                                        }
                                                        _openBranchAllocationPage(
                                                          context,
                                                        );
                                                      },
                                                    ),
                                                  ),

                                                if (showMaxZeroKpiCard)
                                                  SizedBox(
                                                    width: cardWidth,
                                                    child: _KpiCard(
                                                      title: 'Max = 0',
                                                      value:
                                                          '${visibleStats.non}',
                                                      subtitle: '',
                                                      icon:
                                                          Icons.layers_outlined,
                                                      isSelected: false,
                                                    ),
                                                  ),

                                                SizedBox(
                                                  width: cardWidth,
                                                  child: _KpiCard(
                                                    title:
                                                        'Additional Orders Today',
                                                    value:
                                                        '$usedAdditional/$additionalLimit',
                                                    subtitle: '',
                                                    icon:
                                                        Icons.add_box_outlined,
                                                    isSelected: false,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),

                                      const SizedBox(height: 12),

                                      _FiltersBar(
                                        categories: categories,
                                        selectedCategory: s.categoryFilter,
                                        selectedFormulary: s.formularyFilter,
                                        nonWithSales45Only:
                                            s.nonWithSales45Only,
                                        numericFinalOnly: showFullOrderColumns
                                            ? s.numericFinalOnly
                                            : false,
                                        useLimitedStockMode:
                                            useLimitedStockMode,
                                        receivedLast7DaysOnly:
                                            s.receivedLast7DaysOnly,
                                        additionalOnly: s.additionalOnly,
                                        onReceivedLast7DaysChanged: (v) {
                                          context.read<OrdersBloc>().add(
                                            OrdersReceivedLast7DaysToggled(v),
                                          );
                                        },
                                        onCategoryChanged: (v) {
                                          context.read<OrdersBloc>().add(
                                            OrdersCategoryChanged(v),
                                          );
                                        },
                                        onFormularyChanged: (v) {
                                          context.read<OrdersBloc>().add(
                                            OrdersFormularyChanged(v),
                                          );
                                        },
                                        onNonWithSales45Changed: (v) {
                                          context.read<OrdersBloc>().add(
                                            OrdersNonWithSales45Toggled(v),
                                          );
                                        },
                                        onNumericFinalOnlyChanged:
                                            showFullOrderColumns
                                            ? (v) {
                                                context.read<OrdersBloc>().add(
                                                  OrdersNumericFinalOnlyToggled(
                                                    v,
                                                  ),
                                                );
                                              }
                                            : null,
                                        onAdditionalOnlyChanged: (v) {
                                          context.read<OrdersBloc>().add(
                                            OrdersAdditionalOnlyToggled(v),
                                          );
                                        },
                                        isSubmitted: s.isSubmitted,
                                        onClearAll: () {
                                          context.read<OrdersBloc>().add(
                                            const OrdersClearAllFilters(),
                                          );

                                          _grid.resetGridUi();
                                        },
                                      ),

                                      const SizedBox(height: 12),

                                      BlocSelector<
                                        OrdersBloc,
                                        OrdersState,
                                        String
                                      >(
                                        selector: (s) => s.search,
                                        builder: (context, search) {
                                          return BlocBuilder<
                                            BranchZoneCubit,
                                            BranchZoneState
                                          >(
                                            builder: (context, zs) {
                                              final zoneReady =
                                                  zs.zone != null &&
                                                  zs.zone!.trim().isNotEmpty;

                                              return OrdersToolbar(
                                                search: search,
                                                onSearchChanged: (v) {
                                                  context
                                                      .read<OrdersBloc>()
                                                      .add(
                                                        OrdersSearchChanged(v),
                                                      );
                                                },
                                                onOpenColumns: () {
                                                  Scaffold.of(
                                                    context,
                                                  ).openEndDrawer();
                                                },

                                                onExport: () {
                                                  context.read<OrdersBloc>().add(
                                                    const OrdersExportPressed(),
                                                  );
                                                },
                                                showColumnsButton:
                                                    showFullOrderColumns,
                                                statusChip: null,
                                                actions: [
                                                  OrdersToolbar.actionButton(
                                                    label: 'Items To Order',

                                                    icon: Icons
                                                        .shopping_cart_outlined,

                                                    color: Colors.indigo,

                                                    badgeCount:
                                                        s.itemsToOrder.length,

                                                    onPressed: () async {
                                                      await showDialog(
                                                        context: context,
                                                        builder: (_) =>
                                                            BlocProvider.value(
                                                              value: context
                                                                  .read<
                                                                    OrdersBloc
                                                                  >(),
                                                              child:
                                                                  const ItemsToOrderDialog(),
                                                            ),
                                                      );

                                                      if (!context.mounted)
                                                        return;

                                                      context
                                                          .read<OrdersBloc>()
                                                          .add(
                                                            const OrdersLoadItemsToOrder(),
                                                          );
                                                    },
                                                  ),
                                                  const SizedBox(width: 6),
                                                  OrdersToolbar.actionButton(
                                                    label:
                                                        'Additional Order Track',
                                                    icon: Icons
                                                        .track_changes_outlined,
                                                    badgeCount:
                                                        s.trackingPending,
                                                    color:
                                                        AppColors.primaryColor,
                                                    tooltip:
                                                        'Track additional requests status',
                                                    onPressed:
                                                        (!isBusy) ||
                                                            !s.isOrderDay
                                                        ? () {
                                                            BranchOrdersActions.openTrackingDialog(
                                                              context,
                                                            );
                                                          }
                                                        : null,
                                                  ),
                                                  if (showAdditionalRowActions) ...[
                                                    const SizedBox(width: 6),
                                                    OrdersToolbar.actionButton(
                                                      label: 'Send Additional',
                                                      icon: Icons
                                                          .add_box_outlined,
                                                      badgeCount: draftAddCount,
                                                      color: AppColors
                                                          .secondaryColor,
                                                      onPressed:
                                                          (!zoneReady ||
                                                              s
                                                                  .additionalEdits
                                                                  .isEmpty ||
                                                              isBusy)
                                                          ? null
                                                          : () {
                                                              context
                                                                  .read<
                                                                    OrdersBloc
                                                                  >()
                                                                  .add(
                                                                    OrdersSendAdditionalRequestsPressed(
                                                                      zone: zs
                                                                          .zone!,
                                                                    ),
                                                                  );
                                                            },
                                                    ),
                                                  ],

                                                  if (!s.isSubmitted &&
                                                      s.isOrderDay &&
                                                      OperationalDateHelper.canSubmitForBranch(
                                                        startHour:
                                                            s.submitStartHour,
                                                        endHour:
                                                            s.submitEndHour,
                                                      ))
                                                    const SizedBox(width: 6),

                                                  if (!s.isSubmitted &&
                                                      s.isOrderDay &&
                                                      OperationalDateHelper.canSubmitForBranch(
                                                        startHour:
                                                            s.submitStartHour,
                                                        endHour:
                                                            s.submitEndHour,
                                                      ))
                                                    OrdersToolbar.actionButton(
                                                      label:
                                                          'Submit (${s.editsCount})',
                                                      icon: Icons
                                                          .check_circle_outline,
                                                      color: AppColors
                                                          .secondaryColor,
                                                      onPressed:
                                                          (!zoneReady ||
                                                              s.isSubmitted ||
                                                              isBusy ||
                                                              !s.isOrderDay ||
                                                              !OperationalDateHelper.canSubmitForBranch(
                                                                startHour: s
                                                                    .submitStartHour,
                                                                endHour: s
                                                                    .submitEndHour,
                                                              ))
                                                          ? null
                                                          : () async {
                                                              final bloc = context
                                                                  .read<
                                                                    OrdersBloc
                                                                  >();

                                                              final pendingItems = bloc
                                                                  .state
                                                                  .itemsToOrder
                                                                  .where(
                                                                    (e) =>
                                                                        e.status ==
                                                                        'pending',
                                                                  )
                                                                  .toList();

                                                              if (pendingItems
                                                                  .isNotEmpty) {
                                                                final result = await showDialog(
                                                                  context:
                                                                      context,
                                                                  barrierDismissible:
                                                                      false,
                                                                  builder: (_) => PendingItemsToOrderDialog(
                                                                    items:
                                                                        pendingItems,

                                                                    onIgnorePressed: (item) async {
                                                                      await bloc.repo.updateItemToOrderStatus(
                                                                        id: item
                                                                            .id,
                                                                        status:
                                                                            'ignored',
                                                                      );
                                                                    },

                                                                    onAddPressed: (item) async {
                                                                      final row = bloc
                                                                          .state
                                                                          .rows
                                                                          .firstWhere(
                                                                            (
                                                                              e,
                                                                            ) =>
                                                                                e.itemCode ==
                                                                                item.itemCode,
                                                                          );

                                                                      final formulary =
                                                                          (row.branchFormulary ??
                                                                                  '')
                                                                              .toString()
                                                                              .toUpperCase()
                                                                              .trim();

                                                                      final storeStock =
                                                                          (num.tryParse(
                                                                                    row.storeStock.toString(),
                                                                                  ) ??
                                                                                  0)
                                                                              .toInt();

                                                                      final totalReorderToday =
                                                                          (num.tryParse(
                                                                                    row.totalReorderToday.toString(),
                                                                                  ) ??
                                                                                  0)
                                                                              .toInt();

                                                                      final reorderQtyNum =
                                                                          (num.tryParse(
                                                                                    row.reorderQtyNum.toString(),
                                                                                  ) ??
                                                                                  0)
                                                                              .toInt();

                                                                      final hasTma =
                                                                          row.tmaQty !=
                                                                              null &&
                                                                          row.tmaQty.toString() !=
                                                                              '0';

                                                                      final edit = bloc
                                                                          .state
                                                                          .finalEdits[item.itemCode];

                                                                      final int
                                                                      oldQty =
                                                                          edit?.newQty ??
                                                                          (num.tryParse(
                                                                                    row.finalReorderQtyStoreStockGt0.toString(),
                                                                                  ) ??
                                                                                  0)
                                                                              .toInt();

                                                                      final int
                                                                      itemQty = item
                                                                          .qty
                                                                          .toInt();

                                                                      final int
                                                                      newQty =
                                                                          oldQty +
                                                                          itemQty;

                                                                      // =========================
                                                                      // DAILY ORDER WARNING
                                                                      // =========================

                                                                      if (reorderQtyNum >
                                                                          0) {
                                                                        final decision =
                                                                            await showDialog<
                                                                              String
                                                                            >(
                                                                              context: context,
                                                                              builder:
                                                                                  (
                                                                                    _,
                                                                                  ) {
                                                                                    return AlertDialog(
                                                                                      backgroundColor: Colors.white,
                                                                                      title: const Text(
                                                                                        'Already In Daily Order',
                                                                                      ),
                                                                                      content: Text(
                                                                                        'This item already exists in Daily Order.\n\n'
                                                                                        'Daily Order Qty : $reorderQtyNum\n'
                                                                                        'Suggested Qty : $itemQty\n'
                                                                                        'Final Qty : $newQty',
                                                                                      ),
                                                                                      actions: [
                                                                                        FilledButton(
                                                                                          onPressed: () {
                                                                                            Navigator.pop(
                                                                                              context,
                                                                                              'ignore',
                                                                                            );
                                                                                          },
                                                                                          style: FilledButton.styleFrom(
                                                                                            backgroundColor: Colors.red,
                                                                                          ),
                                                                                          child: const Text(
                                                                                            'Ignore',
                                                                                            style: TextStyle(
                                                                                              color: Colors.white,
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                        SizedBox(
                                                                                          width: 10,
                                                                                        ),
                                                                                        FilledButton(
                                                                                          onPressed: () {
                                                                                            Navigator.pop(
                                                                                              context,
                                                                                              'add',
                                                                                            );
                                                                                          },
                                                                                          style: FilledButton.styleFrom(
                                                                                            backgroundColor: AppColors.primaryColor,
                                                                                          ),
                                                                                          child: const Text(
                                                                                            'Add Anyway',
                                                                                            style: TextStyle(
                                                                                              color: Colors.white,
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                      ],
                                                                                    );
                                                                                  },
                                                                            );

                                                                        if (decision ==
                                                                            'ignore') {
                                                                          await bloc.repo.updateItemToOrderStatus(
                                                                            id: item.id,
                                                                            status:
                                                                                'ignored',
                                                                          );

                                                                          return 'ignored';
                                                                        }

                                                                        if (decision !=
                                                                            'add') {
                                                                          return 'ignored';
                                                                        }
                                                                      }

                                                                      // =========================
                                                                      // LIMITED STOCK
                                                                      // =========================

                                                                      final cap = FinalReorderLimitHelper.capForThisBranch(
                                                                        oldSafe:
                                                                            oldQty,
                                                                        storeStock:
                                                                            storeStock,
                                                                        reorderQtyNum:
                                                                            reorderQtyNum,
                                                                        totalReorderToday:
                                                                            totalReorderToday,
                                                                        orderIncreaseLimit: bloc
                                                                            .state
                                                                            .orderIncreaseLimit,
                                                                      );

                                                                      if (newQty >
                                                                          cap) {
                                                                        if (cap <=
                                                                            oldQty) {
                                                                          await showDialog(
                                                                            context:
                                                                                context,
                                                                            builder: (_) => LimitDialog(
                                                                              title: 'Limited Stock',
                                                                              body:
                                                                                  'Current Qty : $oldQty\n'
                                                                                  'Requested Qty : $itemQty\n'
                                                                                  'Max Allowed : $cap\n'
                                                                                  'Final Qty : $newQty',
                                                                            ),
                                                                          );

                                                                          await bloc.repo.updateItemToOrderStatus(
                                                                            id: item.id,
                                                                            status:
                                                                                'ignored',
                                                                          );

                                                                          return 'ignored';
                                                                        }

                                                                        final result =
                                                                            await showDialog<
                                                                              String
                                                                            >(
                                                                              context: context,
                                                                              builder:
                                                                                  (
                                                                                    _,
                                                                                  ) => MaxAllowedDialog(
                                                                                    currentQty: oldQty,
                                                                                    requestedQty: itemQty,
                                                                                    maxAllowed: cap,
                                                                                    finalQty: newQty,
                                                                                  ),
                                                                            );

                                                                        if (result ==
                                                                            'ignore') {
                                                                          await bloc.repo.updateItemToOrderStatus(
                                                                            id: item.id,
                                                                            status:
                                                                                'ignored',
                                                                          );

                                                                          return 'ignored';
                                                                        }

                                                                        if (result ==
                                                                            'add_max') {
                                                                          final correctedQty =
                                                                              cap;

                                                                          bloc.add(
                                                                            OrdersApplyFinalEdit(
                                                                              itemCode: item.itemCode,
                                                                              oldQty: oldQty,
                                                                              newQty: correctedQty,
                                                                              reason: 'Items To Order',
                                                                              applyMaxAdj: false,
                                                                            ),
                                                                          );

                                                                          await bloc.repo.upsertFinalReorderDraft(
                                                                            runDate:
                                                                                bloc.state.runDate,
                                                                            branchName:
                                                                                bloc.state.branchName,
                                                                            itemCode:
                                                                                item.itemCode,
                                                                            itemName:
                                                                                item.itemName,
                                                                            oldQty:
                                                                                oldQty,
                                                                            newQty:
                                                                                correctedQty,
                                                                            reason:
                                                                                'Items To Order',
                                                                            applyMaxAdj:
                                                                                false,
                                                                          );

                                                                          await bloc.repo.updateItemToOrderStatus(
                                                                            id: item.id,
                                                                            status:
                                                                                'processed',
                                                                          );
                                                                          bloc.add(
                                                                            const OrdersLoadItemsToOrder(),
                                                                          );
                                                                          return 'processed';
                                                                        }

                                                                        return null;
                                                                      }

                                                                      // =========================
                                                                      // NON FORMULARY
                                                                      // =========================

                                                                      if (formulary ==
                                                                          'NON') {
                                                                        await showDialog(
                                                                          context:
                                                                              context,
                                                                          builder: (_) => const LimitDialog(
                                                                            title:
                                                                                'NON Formulary',
                                                                            body:
                                                                                'This item is NON formulary and cannot be ordered.',
                                                                          ),
                                                                        );

                                                                        await bloc.repo.updateItemToOrderStatus(
                                                                          id: item
                                                                              .id,
                                                                          status:
                                                                              'ignored',
                                                                        );

                                                                        return 'ignored';
                                                                      }

                                                                      // =========================
                                                                      // TMA WARNING
                                                                      // =========================

                                                                      if (hasTma) {
                                                                        await showDialog(
                                                                          context:
                                                                              context,
                                                                          builder: (_) => const LimitDialog(
                                                                            title:
                                                                                'TMA Item',
                                                                            body:
                                                                                'This item contains TMA quantity.\n'
                                                                                'Please review before ordering.',
                                                                          ),
                                                                        );
                                                                      }

                                                                      // =========================
                                                                      // APPLY EDIT
                                                                      // =========================

                                                                      bloc.add(
                                                                        OrdersApplyFinalEdit(
                                                                          itemCode:
                                                                              item.itemCode,
                                                                          oldQty:
                                                                              oldQty,
                                                                          newQty:
                                                                              newQty,
                                                                          reason:
                                                                              'Items To Order',
                                                                          applyMaxAdj:
                                                                              false,
                                                                        ),
                                                                      );

                                                                      await bloc.repo.upsertFinalReorderDraft(
                                                                        runDate: bloc
                                                                            .state
                                                                            .runDate,
                                                                        branchName: bloc
                                                                            .state
                                                                            .branchName,
                                                                        itemCode:
                                                                            item.itemCode,
                                                                        itemName:
                                                                            item.itemName,
                                                                        oldQty:
                                                                            oldQty,
                                                                        newQty:
                                                                            newQty,
                                                                        reason:
                                                                            'Items To Order',
                                                                        applyMaxAdj:
                                                                            false,
                                                                      );

                                                                      await bloc.repo.updateItemToOrderStatus(
                                                                        id: item
                                                                            .id,
                                                                        status:
                                                                            'processed',
                                                                      );
                                                                      bloc.add(
                                                                        const OrdersLoadItemsToOrder(),
                                                                      );
                                                                      return 'processed';
                                                                    },
                                                                  ),
                                                                );

                                                                if (result !=
                                                                    true) {
                                                                  return;
                                                                }

                                                                bloc.add(
                                                                  const OrdersLoadItemsToOrder(),
                                                                );

                                                                await Future.delayed(
                                                                  const Duration(
                                                                    seconds: 1,
                                                                  ),
                                                                );
                                                              }

                                                              await _openLowDemandSuggestions(
                                                                bloc,
                                                              );
                                                              if (!context
                                                                  .mounted) {
                                                                return;
                                                              }

                                                              // =========================
                                                              // REVIEW CHANGES
                                                              // =========================

                                                              final confirmed =
                                                                  await BranchOrdersActions.openSubmitReviewDialog(
                                                                    context:
                                                                        context,
                                                                    state: context
                                                                        .read<
                                                                          OrdersBloc
                                                                        >()
                                                                        .state,
                                                                    zone: zs
                                                                        .zone!,
                                                                  );

                                                              if (confirmed !=
                                                                  true) {
                                                                return;
                                                              }

                                                              if (!context
                                                                  .mounted)
                                                                return;

                                                              context
                                                                  .read<
                                                                    OrdersBloc
                                                                  >()
                                                                  .add(
                                                                    OrdersSubmitOrderPressed(
                                                                      zone: zs
                                                                          .zone!,
                                                                    ),
                                                                  );
                                                            },
                                                    ),
                                                ],
                                                onClearAll: () {
                                                  context.read<OrdersBloc>().add(
                                                    const OrdersClearAllFilters(),
                                                  );

                                                  _grid.resetGridUi();
                                                },
                                                addMismatch: () {
                                                  BranchOrdersActions.openMismatchPanel(
                                                    context,
                                                  );
                                                },
                                                addMax: () {
                                                  BranchOrdersActions.openMaxPanel(
                                                    context,
                                                  );
                                                },
                                                isOrderDay: s.isOrderDay,
                                              );
                                            },
                                          );
                                        },
                                      ),

                                      const SizedBox(height: 10),

                                      Container(
                                        constraints: BoxConstraints(
                                          minHeight:
                                              MediaQuery.of(
                                                context,
                                              ).size.height *
                                              0.4.h,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE6E8F0),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.04,
                                              ),
                                              blurRadius: 18,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const _TableTitle(),

                                            const SizedBox(height: 10),

                                            SizedBox(
                                              height:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.height *
                                                  0.72,
                                              child: Builder(
                                                builder: (_) {
                                                  final hasActiveFilters =
                                                      s.categoryFilter !=
                                                          'ALL' ||
                                                      s.formularyFilter !=
                                                          'ALL' ||
                                                      s.nonWithSales45Only ||
                                                      s.numericFinalOnly ||
                                                      s.receivedLast7DaysOnly ||
                                                      s.additionalOnly;

                                                  final noResults =
                                                      s.viewRows.isEmpty &&
                                                      s.rows.isNotEmpty;

                                                  if (noResults &&
                                                      hasActiveFilters) {
                                                    return Center(
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .filter_alt_off_outlined,
                                                            size: 54,
                                                            color: Colors.grey,
                                                          ),

                                                          const SizedBox(
                                                            height: 14,
                                                          ),

                                                          const Text(
                                                            'No results found',
                                                            style: TextStyle(
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: Colors
                                                                  .black87,
                                                            ),
                                                          ),

                                                          const SizedBox(
                                                            height: 8,
                                                          ),

                                                          const Text(
                                                            'Current filters are hiding all items',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color:
                                                                  Colors.grey,
                                                            ),
                                                          ),

                                                          const SizedBox(
                                                            height: 18,
                                                          ),

                                                          FilledButton(
                                                            onPressed:
                                                                s.isRemovingFilters
                                                                ? null
                                                                : () {
                                                                    context
                                                                        .read<
                                                                          OrdersBloc
                                                                        >()
                                                                        .add(
                                                                          const OrdersClearFiltersOnly(),
                                                                        );

                                                                    _grid
                                                                        .resetGridUi();
                                                                  },
                                                            style: FilledButton.styleFrom(
                                                              backgroundColor:
                                                                  Colors
                                                                      .redAccent,
                                                              foregroundColor:
                                                                  Colors.white,
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        18,
                                                                    vertical:
                                                                        14,
                                                                  ),
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      14,
                                                                    ),
                                                              ),
                                                            ),
                                                            child:
                                                                s.isRemovingFilters
                                                                ? const SizedBox(
                                                                    width: 18,
                                                                    height: 18,
                                                                    child: CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                      color: Colors
                                                                          .white,
                                                                    ),
                                                                  )
                                                                : const Row(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Icon(
                                                                        Icons
                                                                            .restart_alt,
                                                                      ),
                                                                      SizedBox(
                                                                        width:
                                                                            8,
                                                                      ),
                                                                      Text(
                                                                        'Remove Filters',
                                                                      ),
                                                                    ],
                                                                  ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }

                                                  return OrdersTable(
                                                    rows: s.viewRows,
                                                    isLoading: isBusy,
                                                    orderedColumns:
                                                        orderedColumns,
                                                    columnWidths:
                                                        s.columnWidths,
                                                    finalEdits: s.finalEdits,
                                                    submitStartHour:
                                                        s.submitStartHour,
                                                    submitEndHour:
                                                        s.submitEndHour,
                                                    canEditFinalReorder:
                                                        canEditFinalReorder,
                                                    onTapFinalReorder: (row) {
                                                      final locked =
                                                          !canEditFinalReorder;

                                                      if (locked) {
                                                        return;
                                                      }

                                                      BranchOrdersActions.openFinalSidePanel(
                                                        context: context,
                                                        state: s,
                                                        row: row,
                                                      );
                                                    },
                                                    additionalEdits:
                                                        s.additionalEdits,
                                                    sentAdditionalQtyByItemCode:
                                                        s.sentAdditionalQtyByItemCode,
                                                    showAdditionalRowActions:
                                                        showAdditionalRowActions,
                                                    onTapAdditionalRequest: (row) {
                                                      BranchOrdersActions.openAdditionalSidePanel(
                                                        context: context,
                                                        state: s,
                                                        row: row,
                                                      );
                                                    },
                                                    isSubmitted: s.isSubmitted,
                                                    controller:
                                                        _grid.controller,
                                                    gridController: _grid,
                                                    onColumnResized: (key, width) {
                                                      context
                                                          .read<OrdersBloc>()
                                                          .add(
                                                            OrdersColumnResized(
                                                              columnKey: key,
                                                              width: width,
                                                            ),
                                                          );
                                                    },
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              if (_ordersDrawerOpen)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      setState(() {
                        _ordersDrawerOpen = false;
                      });
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              _OrdersOverlayDrawer(
                open: _ordersDrawerOpen,
                branchName: s.branchName,
                showAllocationPage: _showAllocationPage,
                showStockCheckPage: _showStockCheckPage,
                showInsuranceAssistantPage: showInsuranceAssistantPage,
                insuranceAssistantEnabled: insuranceAssistantEnabled,
                showGuidePage: _showGuidePage,
                hasPendingAllocation: hasAllocationNotice,
                pendingToSend: s.pendingOutgoingAllocationCount,
                incomingCount: s.incomingAllocationTasks.length,
                overdueAllocationCount: allocationInfo.overdueCount,
                pendingStockCheckCount: _stockCheckInfo.pendingCount,
                overdueStockCheckCount: _stockCheckInfo.overdueCount,
                isLoading: s.isBranchAllocationLoading,
                stockCheckLoading: _stockCheckLoading,
                onOpenOrders: _openOrderPage,
                onOpenAllocation: () => _openBranchAllocationPage(context),
                onOpenStockCheck: _openBranchStockCheckPage,
                onOpenInsuranceAssistant: _openInsuranceAssistantPage,
                onOpenGuide: _openGuidePage,
              ),
              _OrdersDrawerToggleButton(
                open: _ordersDrawerOpen,
                showAllocationPage: _showAllocationPage,
                showStockCheckPage: _showStockCheckPage,
                showInsuranceAssistantPage: showInsuranceAssistantPage,
                hasPendingAllocation: hasAllocationNotice,
                pendingToSend: s.pendingOutgoingAllocationCount,
                incomingCount: s.incomingAllocationTasks.length,
                overdueAllocationCount: allocationInfo.overdueCount,
                pendingStockCheckCount: _stockCheckInfo.pendingCount,
                overdueStockCheckCount: _stockCheckInfo.overdueCount,
                onPressed: () {
                  if (_showAllocationPage ||
                      _showStockCheckPage ||
                      showInsuranceAssistantPage ||
                      _showGuidePage) {
                    _openOrderPage();
                    return;
                  }

                  setState(() {
                    _ordersDrawerOpen = !_ordersDrawerOpen;
                  });
                },
              ),

              if (s.isExporting)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: AppColors.primaryColor,
                        ),
                        SizedBox(height: 12),
                        Text(
                          "Exporting file...",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StockCheckPendingInfo {
  final int pendingCount;
  final int overdueCount;
  final DateTime? oldestSentAt;

  const _StockCheckPendingInfo({
    required this.pendingCount,
    required this.overdueCount,
    required this.oldestSentAt,
  });

  bool get hasPending => pendingCount > 0;

  factory _StockCheckPendingInfo.empty() {
    return const _StockCheckPendingInfo(
      pendingCount: 0,
      overdueCount: 0,
      oldestSentAt: null,
    );
  }

  factory _StockCheckPendingInfo.fromRows(List<Map<String, dynamic>> rows) {
    final now = DateTime.now();
    DateTime? oldest;
    var overdue = 0;
    for (final row in rows) {
      final sentAt = DateTime.tryParse((row['sent_at'] ?? '').toString());
      final expiresAt = DateTime.tryParse((row['expires_at'] ?? '').toString());
      if (sentAt != null) {
        if (oldest == null || sentAt.isBefore(oldest)) oldest = sentAt;
      }
      if (_isPastHalfCompletionWindow(
        sentAt: sentAt,
        expiresAt: expiresAt,
        now: now,
      )) {
        overdue++;
      }
    }
    return _StockCheckPendingInfo(
      pendingCount: rows.length,
      overdueCount: overdue,
      oldestSentAt: oldest,
    );
  }
}

class _AllocationPendingInfo {
  final int pendingCount;
  final int overdueCount;

  const _AllocationPendingInfo({
    required this.pendingCount,
    required this.overdueCount,
  });

  factory _AllocationPendingInfo.fromTasks(List<BranchAllocationTask> tasks) {
    final now = DateTime.now();
    var overdue = 0;
    for (final task in tasks) {
      if (_isPastHalfCompletionWindow(
        sentAt: task.sentAt,
        expiresAt: task.expiresAt,
        now: now,
      )) {
        overdue++;
      }
    }
    return _AllocationPendingInfo(
      pendingCount: tasks.length,
      overdueCount: overdue,
    );
  }
}

bool _isPastHalfCompletionWindow({
  required DateTime? sentAt,
  required DateTime? expiresAt,
  required DateTime now,
}) {
  final sent = sentAt?.toLocal();
  final deadline = expiresAt?.toLocal();
  if (deadline == null) return false;
  if (now.isAfter(deadline)) return true;
  if (sent == null || !deadline.isAfter(sent)) return false;

  final totalMinutes = deadline.difference(sent).inMinutes;
  if (totalMinutes <= 0) return true;

  final halfDaysRoundedUp = (totalMinutes / (Duration.minutesPerDay * 2))
      .ceil()
      .clamp(1, 3650);
  final urgentAt = sent.add(Duration(days: halfDaysRoundedUp));
  return !now.isBefore(urgentAt);
}

class _BranchUrgentWorkBanner extends StatefulWidget {
  final bool hasAllocation;
  final int allocationCount;
  final int overdueAllocationCount;
  final bool hasStockCheck;
  final int stockCheckCount;
  final int overdueStockCheckCount;
  final bool stockCheckLoading;
  final VoidCallback onTap;

  const _BranchUrgentWorkBanner({
    required this.hasAllocation,
    required this.allocationCount,
    required this.overdueAllocationCount,
    required this.hasStockCheck,
    required this.stockCheckCount,
    required this.overdueStockCheckCount,
    required this.stockCheckLoading,
    required this.onTap,
  });

  @override
  State<_BranchUrgentWorkBanner> createState() =>
      _BranchUrgentWorkBannerState();
}

class _BranchUrgentWorkBannerState extends State<_BranchUrgentWorkBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasOverdue =
        widget.overdueStockCheckCount > 0 || widget.overdueAllocationCount > 0;
    final borderColor = hasOverdue
        ? const Color(0xFF7F1D1D)
        : widget.hasStockCheck
        ? const Color(0xFF2563EB)
        : const Color(0xFFF59E0B);
    final background = hasOverdue
        ? const Color(0xFFFEE2E2)
        : widget.hasStockCheck
        ? const Color(0xFFEFF6FF)
        : const Color(0xFFFFFBEB);
    final title = hasOverdue
        ? 'Pending Work Needs Action'
        : widget.hasStockCheck && widget.hasAllocation
        ? 'Pending Work'
        : widget.hasStockCheck
        ? 'Stock Check pending'
        : 'Allocation pending';
    final subtitle = hasOverdue
        ? _criticalSubtitle()
        : widget.hasStockCheck && widget.hasAllocation
        ? 'Allocation ${widget.allocationCount} - Stock Check ${widget.stockCheckCount}'
        : widget.hasStockCheck
        ? '${widget.stockCheckCount} item(s) need confirmation'
        : '${widget.allocationCount} item(s) need attention';
    final icon = hasOverdue
        ? Icons.notification_important_rounded
        : widget.hasStockCheck
        ? Icons.inventory_2_rounded
        : Icons.call_made_rounded;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = hasOverdue ? 1 + (_pulseController.value * .018) : 1.0;
        return Transform.scale(scale: pulse, child: child);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            height: widget.hasAllocation && widget.hasStockCheck ? 112 : 98,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor, width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: borderColor.withValues(alpha: .16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: borderColor.withValues(alpha: .25),
                    ),
                  ),
                  child: widget.stockCheckLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(icon, color: borderColor, size: 24),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _PendingWorkSubtitle(
                        hasBoth:
                            !hasOverdue &&
                            widget.hasStockCheck &&
                            widget.hasAllocation,
                        subtitle: subtitle,
                        allocationCount: widget.allocationCount,
                        stockCheckCount: widget.stockCheckCount,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Click to open pending work',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: borderColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.underline,
                              decorationColor: borderColor,
                              decorationThickness: 1.4,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.touch_app_rounded,
                            color: borderColor,
                            size: 14,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  widget.hasAllocation && widget.hasStockCheck
                      ? Icons.dashboard_customize_rounded
                      : Icons.arrow_forward_rounded,
                  color: borderColor,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _criticalSubtitle() {
    final parts = <String>[];
    if (widget.overdueAllocationCount > 0) {
      parts.add('Allocation ${widget.overdueAllocationCount} urgent');
    }
    if (widget.overdueStockCheckCount > 0) {
      parts.add('Stock Check ${widget.overdueStockCheckCount} urgent');
    }
    if (parts.isEmpty) return 'Please Complete Pending Work Now.';
    return parts.join(' - ');
  }
}

class _PendingWorkSubtitle extends StatelessWidget {
  final bool hasBoth;
  final String subtitle;
  final int allocationCount;
  final int stockCheckCount;

  const _PendingWorkSubtitle({
    required this.hasBoth,
    required this.subtitle,
    required this.allocationCount,
    required this.stockCheckCount,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasBoth) {
      return Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      );
    }

    return Wrap(
      spacing: 5,
      runSpacing: 3,
      children: [
        _PendingWorkTypeChip(
          label: 'Allocation',
          count: allocationCount,
          icon: Icons.call_made_rounded,
          color: const Color(0xFFF59E0B),
          italic: true,
        ),
        _PendingWorkTypeChip(
          label: 'Stock Check',
          count: stockCheckCount,
          icon: Icons.inventory_2_rounded,
          color: const Color(0xFF2563EB),
          italic: false,
        ),
      ],
    );
  }
}

class _PendingWorkTypeChip extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool italic;

  const _PendingWorkTypeChip({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.italic,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            '$label $count',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: italic ? FontWeight.w800 : FontWeight.w900,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerAlertSummary extends StatelessWidget {
  final int allocationCount;
  final int overdueAllocationCount;
  final int stockCheckCount;
  final int overdueStockCheckCount;
  final bool loading;

  const _DrawerAlertSummary({
    required this.allocationCount,
    required this.overdueAllocationCount,
    required this.stockCheckCount,
    required this.overdueStockCheckCount,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final hasOverdue = overdueStockCheckCount > 0 || overdueAllocationCount > 0;
    final title = hasOverdue ? 'Urgent pending work' : 'Pending work';
    final subtitle = hasOverdue
        ? 'Allocation $overdueAllocationCount urgent - Stock Check $overdueStockCheckCount urgent'
        : 'Allocation $allocationCount - Stock Check $stockCheckCount';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: hasOverdue
                  ? const Color(0xFFFFF1F2)
                  : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    hasOverdue
                        ? Icons.notification_important_rounded
                        : Icons.notifications_active_rounded,
                    color: hasOverdue
                        ? const Color(0xFF7F1D1D)
                        : const Color(0xFFF97316),
                    size: 19,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingTabIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;

  const _PendingTabIcon({
    required this.icon,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 21),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: .25)),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _OrdersOverlayDrawer extends StatelessWidget {
  static const double width = 292;

  final bool open;
  final String branchName;
  final bool showAllocationPage;
  final bool showStockCheckPage;
  final bool showInsuranceAssistantPage;
  final bool insuranceAssistantEnabled;
  final bool showGuidePage;
  final bool hasPendingAllocation;
  final int pendingToSend;
  final int incomingCount;
  final int overdueAllocationCount;
  final int pendingStockCheckCount;
  final int overdueStockCheckCount;
  final bool isLoading;
  final bool stockCheckLoading;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenAllocation;
  final VoidCallback onOpenStockCheck;
  final VoidCallback onOpenInsuranceAssistant;
  final VoidCallback onOpenGuide;

  const _OrdersOverlayDrawer({
    required this.open,
    required this.branchName,
    required this.showAllocationPage,
    required this.showStockCheckPage,
    required this.showInsuranceAssistantPage,
    required this.insuranceAssistantEnabled,
    required this.showGuidePage,
    required this.hasPendingAllocation,
    required this.pendingToSend,
    required this.incomingCount,
    required this.overdueAllocationCount,
    required this.pendingStockCheckCount,
    required this.overdueStockCheckCount,
    required this.isLoading,
    required this.stockCheckLoading,
    required this.onOpenOrders,
    required this.onOpenAllocation,
    required this.onOpenStockCheck,
    required this.onOpenInsuranceAssistant,
    required this.onOpenGuide,
  });

  @override
  Widget build(BuildContext context) {
    final totalAllocation = pendingToSend + incomingCount;
    final hasPendingStockCheck = pendingStockCheckCount > 0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      top: 0,
      bottom: 0,
      left: open ? 0 : -width,
      width: width,
      child: IgnorePointer(
        ignoring: !open,
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 10, 0, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFD9E8F5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 30,
                  offset: const Offset(8, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                              ),
                              child: const Icon(
                                Icons.dashboard_customize_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Branch Workspace',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    branchName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.86,
                                      ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (hasPendingAllocation || hasPendingStockCheck) ...[
                          const SizedBox(height: 14),
                          _DrawerAlertSummary(
                            allocationCount: totalAllocation,
                            overdueAllocationCount: overdueAllocationCount,
                            stockCheckCount: pendingStockCheckCount,
                            overdueStockCheckCount: overdueStockCheckCount,
                            loading: isLoading || stockCheckLoading,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _OrdersDrawerItem(
                            icon: Icons.shopping_cart_checkout_rounded,
                            title: 'Orders',
                            subtitle: 'Daily order workspace',
                            selected:
                                !showAllocationPage &&
                                !showStockCheckPage &&
                                !showInsuranceAssistantPage &&
                                !showGuidePage,
                            color: const Color(0xFF0EA5E9),
                            onTap: onOpenOrders,
                          ),
                          const SizedBox(height: 10),
                          _OrdersDrawerItem(
                            icon: Icons.account_tree_rounded,
                            title: 'Allocation',
                            subtitle: pendingToSend > 0 || incomingCount > 0
                                ? overdueAllocationCount > 0
                                      ? '$totalAllocation pending - $overdueAllocationCount urgent'
                                      : 'To send $pendingToSend - Incoming $incomingCount'
                                : 'No pending allocation',
                            selected: showAllocationPage,
                            color: overdueAllocationCount > 0
                                ? const Color(0xFF7F1D1D)
                                : const Color(0xFFF59E0B),
                            badge: totalAllocation > 0
                                ? totalAllocation.toString()
                                : null,
                            onTap: onOpenAllocation,
                          ),
                          const SizedBox(height: 10),
                          _OrdersDrawerItem(
                            icon: overdueStockCheckCount > 0
                                ? Icons.notification_important_rounded
                                : Icons.inventory_2_rounded,
                            title: 'Stock Check',
                            subtitle: pendingStockCheckCount > 0
                                ? overdueStockCheckCount > 0
                                      ? '$pendingStockCheckCount pending - $overdueStockCheckCount urgent'
                                      : '$pendingStockCheckCount pending check(s)'
                                : 'No pending stock check',
                            selected: showStockCheckPage,
                            color: overdueStockCheckCount > 0
                                ? const Color(0xFF7F1D1D)
                                : const Color(0xFF2563EB),
                            badge: pendingStockCheckCount > 0
                                ? pendingStockCheckCount.toString()
                                : null,
                            onTap: onOpenStockCheck,
                          ),
                          if (insuranceAssistantEnabled) ...[
                            const SizedBox(height: 10),
                            _OrdersDrawerItem(
                              key: const ValueKey(
                                'orders-insurance-assistant-entry',
                              ),
                              icon: Icons.auto_awesome_rounded,
                              title: 'Insurance AI',
                              subtitle: 'Coverage & clinical knowledge',
                              selected: showInsuranceAssistantPage,
                              color: const Color(0xFF6D5DFB),
                              badge: 'AI',
                              onTap: onOpenInsuranceAssistant,
                            ),
                          ],
                          const SizedBox(height: 10),
                          _OrdersDrawerItem(
                            icon: Icons.menu_book_rounded,
                            title: 'Order Guide',
                            subtitle: 'How orders, edits & submission work',
                            selected: showGuidePage,
                            color: const Color(0xFF7C3AED),
                            badge: 'NEW',
                            onTap: onOpenGuide,
                          ),
                          const Spacer(),
                          const Divider(height: 28, color: AppColors.border),
                          _DrawerLogoutButton(),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: const Text(
                              'The drawer floats over the order page, so your table keeps its full width.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrdersDrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _OrdersDrawerItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.11) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.35)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: selected ? color : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersDrawerToggleButton extends StatefulWidget {
  final bool open;
  final bool showAllocationPage;
  final bool showStockCheckPage;
  final bool showInsuranceAssistantPage;
  final bool hasPendingAllocation;
  final int pendingToSend;
  final int incomingCount;
  final int overdueAllocationCount;
  final int pendingStockCheckCount;
  final int overdueStockCheckCount;
  final VoidCallback onPressed;

  const _OrdersDrawerToggleButton({
    required this.open,
    required this.showAllocationPage,
    required this.showStockCheckPage,
    required this.showInsuranceAssistantPage,
    required this.hasPendingAllocation,
    required this.pendingToSend,
    required this.incomingCount,
    required this.overdueAllocationCount,
    required this.pendingStockCheckCount,
    required this.overdueStockCheckCount,
    required this.onPressed,
  });

  @override
  State<_OrdersDrawerToggleButton> createState() =>
      _OrdersDrawerToggleButtonState();
}

class _OrdersDrawerToggleButtonState extends State<_OrdersDrawerToggleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.pendingToSend + widget.incomingCount;
    final hasPendingStockCheck = widget.pendingStockCheckCount > 0;
    final showBackToOrders =
        (widget.showAllocationPage ||
            widget.showStockCheckPage ||
            widget.showInsuranceAssistantPage) &&
        !widget.open;
    final showPendingLabel =
        (widget.hasPendingAllocation || hasPendingStockCheck) &&
        !widget.open &&
        !widget.showAllocationPage &&
        !widget.showStockCheckPage &&
        !widget.showInsuranceAssistantPage;
    final compactPendingTab = showPendingLabel;
    final showLabel = showBackToOrders;
    final label = showBackToOrders ? 'Go to Order Page' : 'Pending work';
    final hasUrgentPending =
        widget.overdueAllocationCount > 0 || widget.overdueStockCheckCount > 0;
    final foregroundColor = showBackToOrders
        ? Colors.white
        : hasUrgentPending
        ? const Color(0xFF991B1B)
        : const Color(0xFF92400E);
    final backgroundColor = showBackToOrders
        ? widget.showInsuranceAssistantPage
              ? const Color(0xFF6D5DFB)
              : widget.showStockCheckPage
              ? const Color(0xFF2563EB)
              : const Color(0xFFF59E0B)
        : widget.showAllocationPage
        ? const Color(0xFFF59E0B)
        : widget.showStockCheckPage
        ? const Color(0xFF2563EB)
        : Colors.white;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      left: widget.open
          ? _OrdersOverlayDrawer.width + 8
          : compactPendingTab
          ? 0
          : 10,
      top: compactPendingTab ? 118 : 18,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulse = showBackToOrders || compactPendingTab
              ? 1 + (_pulseController.value * 0.035)
              : 1.0;
          return Transform.scale(
            scale: pulse,
            alignment: Alignment.centerLeft,
            child: child,
          );
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: compactPendingTab
                ? const BorderRadius.horizontal(right: Radius.circular(999))
                : BorderRadius.circular(999),
            onTap: widget.onPressed,
            child: Tooltip(
              message: compactPendingTab
                  ? 'Pending work: allocation $total, stock check ${widget.pendingStockCheckCount}'
                  : label,
              waitDuration: const Duration(milliseconds: 350),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: compactPendingTab
                    ? const EdgeInsets.fromLTRB(12, 12, 10, 12)
                    : EdgeInsets.fromLTRB(
                        showBackToOrders ? 8 : (showLabel ? 12 : 10),
                        9,
                        showLabel ? 14 : 10,
                        9,
                      ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: compactPendingTab
                      ? const BorderRadius.horizontal(
                          right: Radius.circular(999),
                        )
                      : BorderRadius.circular(999),
                  border: Border.all(
                    color:
                        widget.hasPendingAllocation ||
                            hasPendingStockCheck ||
                            showBackToOrders
                        ? hasUrgentPending
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFFF59E0B)
                        : const Color(0xFFD9E8F5),
                    width: showBackToOrders || compactPendingTab ? 1.4 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (widget.hasPendingAllocation ||
                                      hasPendingStockCheck ||
                                      showBackToOrders
                                  ? hasUrgentPending
                                        ? const Color(0xFF7F1D1D)
                                        : const Color(0xFFF59E0B)
                                  : Colors.black)
                              .withValues(
                                alpha:
                                    widget.hasPendingAllocation ||
                                        hasPendingStockCheck ||
                                        showBackToOrders
                                    ? 0.34
                                    : 0.12,
                              ),
                      blurRadius:
                          widget.hasPendingAllocation ||
                              hasPendingStockCheck ||
                              showBackToOrders
                          ? 26
                          : 14,
                      offset: const Offset(0, 9),
                    ),
                  ],
                ),
                child: compactPendingTab
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.hasPendingAllocation)
                            _PendingTabIcon(
                              icon: Icons.account_tree_rounded,
                              count: total,
                              color: widget.overdueAllocationCount > 0
                                  ? const Color(0xFF7F1D1D)
                                  : const Color(0xFFF59E0B),
                            ),
                          if (widget.hasPendingAllocation &&
                              hasPendingStockCheck)
                            const SizedBox(width: 7),
                          if (hasPendingStockCheck)
                            _PendingTabIcon(
                              icon: Icons.inventory_2_rounded,
                              count: widget.pendingStockCheckCount,
                              color: widget.overdueStockCheckCount > 0
                                  ? const Color(0xFF7F1D1D)
                                  : const Color(0xFF2563EB),
                            ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedRotation(
                            turns: widget.open || showBackToOrders ? 0.5 : 0,
                            duration: const Duration(milliseconds: 220),
                            child: Container(
                              width: showBackToOrders ? 30 : 22,
                              height: showBackToOrders ? 30 : 22,
                              decoration: BoxDecoration(
                                color: showBackToOrders
                                    ? Colors.white.withValues(alpha: 0.20)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Icon(
                                Icons.keyboard_double_arrow_right_rounded,
                                color:
                                    widget.showAllocationPage ||
                                        widget.showStockCheckPage
                                    ? Colors.white
                                    : const Color(0xFF0EA5E9),
                                size: showBackToOrders ? 24 : 21,
                              ),
                            ),
                          ),
                          if (showLabel) ...[
                            SizedBox(width: showBackToOrders ? 9 : 8),
                            Text(
                              label,
                              style: TextStyle(
                                color: foregroundColor,
                                fontWeight: FontWeight.w900,
                                fontSize: showBackToOrders ? 13.5 : 12,
                                letterSpacing: showBackToOrders ? 0.1 : 0,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatefulWidget {
  final bool isSubmitted;
  final bool isOrderDay;
  final bool isMissingOrder;
  final String runDate;
  final String? nextOrderDate;
  final String? nextPreparationAt;
  final String? nextPreparationDeadlineAt;

  const _StatusChip({
    required this.isSubmitted,
    required this.isOrderDay,
    required this.isMissingOrder,
    required this.runDate,
    required this.nextOrderDate,
    required this.nextPreparationAt,
    required this.nextPreparationDeadlineAt,
  });

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = OperationalDateHelper.nowUae;
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _StatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runDate != widget.runDate ||
        oldWidget.isOrderDay != widget.isOrderDay ||
        oldWidget.isSubmitted != widget.isSubmitted ||
        oldWidget.nextPreparationAt != widget.nextPreparationAt ||
        oldWidget.nextPreparationDeadlineAt !=
            widget.nextPreparationDeadlineAt) {
      _now = OperationalDateHelper.nowUae;
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!_shouldCountDown) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = OperationalDateHelper.nowUae;
        if (!_shouldCountDown) {
          _timer?.cancel();
          _timer = null;
        }
      });
    });
  }

  DateTime? get _preparationAt =>
      _parseDisplayDateTime(widget.nextPreparationAt);

  DateTime? get _deadlineAt =>
      _parseDisplayDateTime(widget.nextPreparationDeadlineAt);

  DateTime? _parseDisplayDateTime(String? value) {
    final parsed = DateTime.tryParse(value ?? '');
    if (parsed == null) return null;
    return UaeDateTimeFormatter.toUae(parsed);
  }

  bool get _shouldCountDown {
    if (widget.isSubmitted) return false;

    final target = widget.isOrderDay ? _deadlineAt : _preparationAt;
    return target != null && _now.isBefore(target);
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color br;
    Color fg;
    String text;
    IconData icon;
    String? detail;

    if (widget.isSubmitted) {
      bg = const Color(0xFFECFDF3);
      br = const Color(0xFFABEFC6);
      fg = const Color(0xFF027A48);
      text = 'Submitted';
      icon = Icons.check_circle;
      detail = _nextOrderPreparationMessage();
    } else if (widget.isMissingOrder) {
      bg = const Color(0xFFFEF3F2);
      br = const Color(0xFFFDA29B);
      fg = const Color(0xFFB42318);
      text = 'Missing Order';
      icon = Icons.warning_amber_rounded;
      detail = _nextOrderPreparationMessage();
    } else if (!widget.isOrderDay) {
      bg = const Color(0xFFFFF1F2);
      br = const Color(0xFFFDA4AF);
      fg = const Color(0xFFB42318);
      text = 'No Order Today';
      icon = Icons.block;
      detail = _futurePreparationMessage();
    } else {
      bg = const Color(0xFFFFFBEB);
      br = const Color(0xFFFDE68A);
      fg = const Color(0xFF92400E);
      text = 'Draft';
      icon = Icons.edit_outlined;
      detail = _activeWindowMessage('Submit ends');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontWeight: FontWeight.w900, color: fg),
          ),
          if (detail != null) ...[
            Container(
              height: 16,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: br,
            ),
            Icon(Icons.schedule_rounded, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(
              detail,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: fg,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatReadableDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    final uaeDate = UaeDateTimeFormatter.toUae(date);

    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final dayName = days[uaeDate.weekday - 1];
    final d = uaeDate.day.toString().padLeft(2, '0');
    final m = uaeDate.month.toString().padLeft(2, '0');
    final y = uaeDate.year.toString().padLeft(4, '0');
    return '$dayName $d-$m-$y';
  }

  String? _futurePreparationMessage() {
    final preparationAt = _preparationAt;
    if (preparationAt == null) {
      return widget.nextOrderDate == null
          ? null
          : 'Next order: ${_formatReadableDate(widget.nextOrderDate!)}';
    }

    final prepDay = DateTime(
      preparationAt.year,
      preparationAt.month,
      preparationAt.day,
    );
    final today = DateTime(_now.year, _now.month, _now.day);
    final time = _formatClock(preparationAt);

    if (prepDay == today) {
      final countdown = _now.isBefore(preparationAt)
          ? ' - starts in ${_formatDuration(preparationAt.difference(_now))}'
          : '';
      return 'Prepared today at $time$countdown';
    }

    return 'Prepared ${_formatReadableDate(preparationAt.toIso8601String())} at $time';
  }

  String _nextOrderPreparationMessage() {
    final nextOrder = widget.nextOrderDate == null
        ? 'Next order'
        : 'Next: ${_formatReadableDate(widget.nextOrderDate!)}';
    final preparationAt = _preparationAt;

    if (preparationAt == null) return nextOrder;

    final prepDay = DateTime(
      preparationAt.year,
      preparationAt.month,
      preparationAt.day,
    );
    final today = DateTime(_now.year, _now.month, _now.day);
    final when = prepDay == today
        ? 'today'
        : _formatReadableDate(preparationAt.toIso8601String());

    return '$nextOrder - prepare $when at ${_formatClock(preparationAt)}';
  }

  String _activeWindowMessage(String label) {
    final deadlineAt = _deadlineAt;
    if (deadlineAt == null) return 'Order window is open';

    if (_now.isBefore(deadlineAt)) {
      return '$label in ${_formatDuration(deadlineAt.difference(_now))}';
    }

    return 'Window closed at ${_formatClock(deadlineAt)}';
  }

  String _formatClock(DateTime date) {
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $suffix';
  }

  String _formatDuration(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final hours = safe.inHours.toString().padLeft(2, '0');
    final minutes = (safe.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (safe.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

class _ZoneChip extends StatelessWidget {
  final String? zone;
  const _ZoneChip({required this.zone});

  @override
  Widget build(BuildContext context) {
    final z = (zone ?? '').trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_outlined, size: 16, color: Color(0xFF111827)),
          const SizedBox(width: 6),
          Text(
            z.isEmpty ? 'Zone: -' : z,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? right;

  const _TopHeader({required this.title, required this.subtitle, this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 90.w,
                height: 50.h,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/logo1.png"),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryColor,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.secondaryColor,
                          AppColors.primaryColor,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SelectableText(
                      title,
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w900,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              //   SizedBox(width: 20.w),
              //  _LogoutIconButton(),
            ],
          ),
        ),
        ?right,
      ],
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  final int progress;
  final String message;

  const _ProgressStrip({required this.progress, required this.message});

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync, size: 18, color: AppColors.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '$p/100',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: p / 100.0,
              minHeight: 8,
              color: AppColors.primaryColor,

              backgroundColor: const Color(0xFFE5E7EB),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 98,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? AppColors.primaryColor : const Color(0xFFE6E8F0),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E8F0)),
            ),
            child: Icon(icon, color: AppColors.primaryColor, size: 18.h),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w900,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final String selectedFormulary;
  final bool nonWithSales45Only;
  final bool numericFinalOnly;
  final bool receivedLast7DaysOnly;

  final ValueChanged<bool> onReceivedLast7DaysChanged;
  final bool additionalOnly;

  final bool isSubmitted;
  final bool useLimitedStockMode;
  final ValueChanged<bool> onAdditionalOnlyChanged;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onFormularyChanged;
  final ValueChanged<bool> onNonWithSales45Changed;
  final ValueChanged<bool>? onNumericFinalOnlyChanged;
  final VoidCallback onClearAll;
  const _FiltersBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.selectedFormulary,
    required this.nonWithSales45Only,
    required this.numericFinalOnly,
    required this.additionalOnly,

    /// NEW
    required this.isSubmitted,

    required this.onAdditionalOnlyChanged,
    required this.onCategoryChanged,
    required this.onFormularyChanged,
    required this.onNonWithSales45Changed,
    this.onNumericFinalOnlyChanged,
    required this.receivedLast7DaysOnly,
    required this.onReceivedLast7DaysChanged,
    required this.onClearAll,
    required this.useLimitedStockMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          double itemWidth;

          itemWidth = 310.w;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: itemWidth,
                child: _ModernDropdown(
                  label: 'Category',
                  value: selectedCategory,
                  items: categories,
                  onChanged: onCategoryChanged,
                ),
              ),

              /*   SizedBox(
                  width: itemWidth,
                  child: _ModernDropdown(
                    label: 'Formulary',
                    value: selectedFormulary,
                    items: const [
                      'ALL',
                      'ESSENTIAL',
                      'NON',
                      'SALES',
                      'TMA',
    /// NEW
                    ],
                    onChanged: onFormularyChanged,
                  ),
                ),*/
              SizedBox(
                width: itemWidth,
                child: _ReceivedLast7DaysTile(
                  value: receivedLast7DaysOnly,
                  useLimitedStockMode: useLimitedStockMode,
                  onChanged: onReceivedLast7DaysChanged,
                ),
              ),

              SizedBox(
                width: itemWidth,
                child: _SwitchTile(
                  title: 'Max 0 + Sales (45d)',
                  subtitle: 'Show Max Adj = 0 with sales > 0',
                  value: nonWithSales45Only,
                  onChanged: onNonWithSales45Changed,
                ),
              ),

              SizedBox(
                width: itemWidth,
                child: _SwitchTile(
                  title: 'Available Item in Order',
                  subtitle: '',
                  value: numericFinalOnly,
                  onChanged: onNumericFinalOnlyChanged,
                ),
              ),

              SizedBox(
                width: itemWidth,
                child: _SwitchTile(
                  title: 'Additional Only',
                  subtitle: 'Show items with additional requests',
                  value: additionalOnly,
                  onChanged: onAdditionalOnlyChanged,
                ),
              ),
              SizedBox(
                width: 160.w,
                height: 45.h,
                child: ElevatedButton.icon(
                  onPressed: onClearAll,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text(
                    'Clear Filters',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModernDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _ModernDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.backgroundWidget,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4338CA), width: 1.4),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14.r),

      onTap: onChanged == null ? null : () => onChanged!(!value),

      child: Container(
        height: 80.h,
        padding: const EdgeInsets.symmetric(horizontal: 12),

        decoration: BoxDecoration(
          color: value
              ? AppColors.primaryColor.withValues(alpha: 0.08)
              : AppColors.backgroundWidget,

          borderRadius: BorderRadius.circular(14.r),

          border: Border.all(
            color: value ? AppColors.primaryColor : const Color(0xFFE6E8F0),

            width: value ? 2 : 1,
          ),
        ),

        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.sp,
                      color: AppColors.secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),

            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primaryColor,
              inactiveThumbColor: AppColors.secondaryColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _TableTitle extends StatelessWidget {
  const _TableTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.table_rows_outlined, color: AppColors.primaryColor),
        SizedBox(width: 8),
        Text(
          'Main Table',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

class _DrawerLogoutButton extends StatelessWidget {
  Future<bool> _confirmLogout(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
            title: const Row(
              children: [
                _LogoutDialogIcon(),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Log out?',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              'You will return to the sign-in page. Any unsaved changes on this page will be lost.',
              style: TextStyle(
                color: AppColors.subText,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'Log out',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.status != current.status &&
          (previous.isSigningOut || current.status == AuthStatus.failure),
      listener: (context, state) {
        if (state.status == AuthStatus.failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error ?? 'Logout failed. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (!state.isSigningOut) {
          context.go('/login');
        }
      },
      builder: (context, state) {
        final loading = state.isSigningOut;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: loading
                ? null
                : () async {
                    final confirmed = await _confirmLogout(context);
                    if (!context.mounted || !confirmed) return;
                    context.read<AuthBloc>().add(AuthLogoutRequested());
                  },
            child: Ink(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: loading
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.3,
                                color: Color(0xFFDC2626),
                              ),
                            )
                          : const Icon(
                              Icons.logout_rounded,
                              size: 19,
                              color: Color(0xFFDC2626),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        loading ? 'Signing out...' : 'Log out',
                        style: const TextStyle(
                          color: Color(0xFF991B1B),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (!loading)
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFB91C1C),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LogoutDialogIcon extends StatelessWidget {
  const _LogoutDialogIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: const Icon(
        Icons.logout_rounded,
        color: Color(0xFFDC2626),
        size: 21,
      ),
    );
  }
}

class _EditLimitChip extends StatelessWidget {
  final int used;
  final int limit;

  const _EditLimitChip({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final remaining = (limit - used).clamp(0, limit);

    Color bg;
    Color border;
    Color fg;

    if (remaining <= 3) {
      bg = const Color(0xFFFEF2F2);
      border = const Color(0xFFFCA5A5);
      fg = const Color(0xFFB91C1C);
    } else {
      bg = const Color(0xFFEFF6FF);
      border = const Color(0xFFBFDBFE);
      fg = const Color(0xFF1D4ED8);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note_outlined, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            '$used/$limit',
            style: TextStyle(fontWeight: FontWeight.w900, color: fg),
          ),
        ],
      ),
    );
  }
}

class _ReceivedLast7DaysTile extends StatelessWidget {
  final bool value;
  final bool useLimitedStockMode;
  final ValueChanged<bool> onChanged;

  const _ReceivedLast7DaysTile({
    required this.value,
    required this.useLimitedStockMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!value),

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),

        height: 80.h,

        padding: const EdgeInsets.symmetric(horizontal: 12),

        decoration: BoxDecoration(
          color: value
              ? AppColors.primaryColor.withValues(alpha: .08)
              : AppColors.backgroundWidget,

          borderRadius: BorderRadius.circular(14),

          border: Border.all(
            color: useLimitedStockMode ? Colors.orange : Colors.green,
            width: 2,
          ),
        ),

        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  const Text(
                    'Item Received Last 7 Days',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),

                  const SizedBox(height: 4),

                  AnimatedSwitcher(
                    duration: Duration(milliseconds: 400),

                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(0, .2),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),

                    child: Text(
                      useLimitedStockMode
                          ? 'Received + Store Stock + Can Add It'
                          : 'Received + Store Stock > 0',

                      key: ValueKey(useLimitedStockMode),

                      style: TextStyle(
                        fontSize: 11.sp,
                        color: useLimitedStockMode
                            ? Colors.orange
                            : Colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primaryColor,
              inactiveThumbColor: AppColors.secondaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
