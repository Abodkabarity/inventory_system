import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/operational_date_helper.dart';
import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';
import '../final_reorder/widgets/limit_dialog.dart';
import '../widgets/branch_zone_cubit.dart';
import '../widgets/orders_grid_controller.dart';
import '../widgets/orders_table.dart';
import '../widgets/orders_toolbar.dart';
import '../widgets/pending_items_to_order_dialog.dart';
import 'branch_orders_actions.dart';
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

  bool _newDayDialogVisible = false;

  String? _lastDialogDate;
  @override
  void initState() {
    super.initState();

    _grid = OrdersGridController();

    _startOperationalWatcher();
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

      // 🔥 already on latest operational order
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('UAE NOW: ${OperationalDateHelper.nowUae}');
    return BlocBuilder<OrdersBloc, OrdersState>(
      builder: (context, s) {
        final isBusy = s.isBusy;

        final statsAll = BranchOrdersSelectors.calcStats(s.rows);
        final categories = BranchOrdersSelectors.extractCategories(s.rows);

        final orderedColumns = s.isOrderDay
            ? BranchOrdersSelectors.orderedVisibleColumns(s)
            : ['item_code', 'item_name', 'branch_stock', 'store_stock'];

        final draftAddCount = s.additionalCount;

        final usedAdditional = s.usedAdditionalOrders;

        final additionalLimit = s.additionalOrderLimit.toInt();

        return SelectionArea(
          child: Scaffold(
            backgroundColor: const Color(0xFFF6F7FB),
            endDrawer: const ColumnsPanel(),
            body: Stack(
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        BlocBuilder<BranchZoneCubit, BranchZoneState>(
                          builder: (context, zs) {
                            return _TopHeader(
                              title: s.branchName,
                              subtitle: 'Orders • ${s.runDate}',
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
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                          ),

                                          title: const Row(
                                            children: [
                                              Icon(
                                                Icons.save_outlined,
                                                color: AppColors.primaryColor,
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
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),

                                              SizedBox(height: 12),

                                              Text(
                                                '✓ Visible / Hidden Columns',
                                              ),

                                              SizedBox(height: 4),

                                              Text('✓ Column Arrangement'),

                                              SizedBox(height: 4),

                                              Text('✓ Column Widths'),

                                              SizedBox(height: 12),

                                              Text(
                                                'The layout will be restored automatically after refresh or login.',
                                              ),
                                            ],
                                          ),

                                          actions: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(context, false);
                                              },
                                              child: const Text(
                                                'Cancel',
                                                style: TextStyle(
                                                  color:
                                                      AppColors.secondaryColor,
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

                                              style: OutlinedButton.styleFrom(
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
                                                        Text('Reset Layout'),
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
                                                          Icons.delete_forever,
                                                        ),
                                                        label: const Text(
                                                          'Reset',
                                                        ),
                                                        style:
                                                            FilledButton.styleFrom(
                                                              backgroundColor:
                                                                  Colors.red,
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

                                                if (!context.mounted) return;

                                                context.read<OrdersBloc>().add(
                                                  const OrdersDeleteUiSettings(),
                                                );

                                                Navigator.pop(context, false);

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
                                                Navigator.pop(context, true);
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
                                    icon: const Icon(Icons.download, size: 18),
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
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  /*  FilledButton.icon(
                                    onPressed: () {
                                      BranchOrdersActions.openHistoryExportDialog(
                                        context,
                                      );
                                    },
                                    icon: const Icon(Icons.history),
                                    label: const Text(
                                      'History',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.deepPurple,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),*/
                                  _StatusChip(
                                    isSubmitted: s.isSubmitted,
                                    isOrderDay: s.isOrderDay,
                                    isMissingOrder:
                                        s.isOrderDay &&
                                        !s.isSubmitted &&
                                        OperationalDateHelper.isMissingWindowForBranch(
                                          startHour: s.submitStartHour,
                                          endHour: s.submitEndHour,
                                        ),
                                  ),

                                  const SizedBox(width: 10),

                                  _EditLimitChip(
                                    used: s.finalEdits.length,
                                    limit: s.orderEditLimit,
                                  ),

                                  const SizedBox(width: 10),

                                  _ZoneChip(zone: zs.zone),
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
                                        MediaQuery.of(context).size.height * .7,
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
                                              minimumSize: Size(250.w, 45.h),
                                              elevation: 20,
                                              shadowColor:
                                                  AppColors.secondaryColor,
                                            ),
                                            label: Text(
                                              'Create Order',
                                              style: TextStyle(fontSize: 18.sp),
                                            ),
                                            onPressed: () {
                                              context.read<OrdersBloc>().add(
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
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE6E8F0),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.05,
                                              ),
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
                                            s.progressMessage ?? 'Working...',
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
                                      final double cardWidth = 300.w;

                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          SizedBox(
                                            width: cardWidth,
                                            child: _KpiCard(
                                              title: 'Total Products',
                                              value: statsAll.totalProducts
                                                  .toString(),
                                              subtitle: 'All APG Items',
                                              icon: Icons.list_alt_outlined,
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
                                                value: statsAll
                                                    .finalReorderCount
                                                    .round()
                                                    .toString(),
                                                subtitle: '',
                                                icon:
                                                    Icons.inventory_2_outlined,
                                                isSelected: s.numericFinalOnly,
                                              ),
                                            ),
                                          ),

                                          SizedBox(
                                            width: cardWidth,
                                            child: _KpiCard(
                                              title: 'Non',
                                              value: '${statsAll.non}',
                                              subtitle: '',
                                              icon: Icons.layers_outlined,
                                              isSelected: false,
                                            ),
                                          ),

                                          SizedBox(
                                            width: cardWidth,
                                            child: _KpiCard(
                                              title: 'Additional Orders Today',
                                              value:
                                                  '$usedAdditional/$additionalLimit',
                                              subtitle: '',
                                              icon: Icons.add_box_outlined,
                                              isSelected: false,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 12),

                                  _FiltersBar(
                                    categories: categories,
                                    selectedCategory: s.categoryFilter,
                                    selectedFormulary: s.formularyFilter,
                                    nonWithSales45Only: s.nonWithSales45Only,
                                    numericFinalOnly: s.isOrderDay
                                        ? s.numericFinalOnly
                                        : false,
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
                                    onNumericFinalOnlyChanged: s.isOrderDay
                                        ? (v) {
                                            context.read<OrdersBloc>().add(
                                              OrdersNumericFinalOnlyToggled(v),
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

                                  BlocSelector<OrdersBloc, OrdersState, String>(
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
                                              context.read<OrdersBloc>().add(
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
                                            statusChip: null,
                                            actions: [
                                              OrdersToolbar.actionButton(
                                                label: 'Additional Order Track',
                                                icon: Icons
                                                    .track_changes_outlined,
                                                badgeCount: s.trackingPending,
                                                color: AppColors.primaryColor,
                                                tooltip:
                                                    'Track additional requests status',
                                                onPressed:
                                                    (!isBusy) || !s.isOrderDay
                                                    ? () {
                                                        BranchOrdersActions.openTrackingDialog(
                                                          context,
                                                        );
                                                      }
                                                    : null,
                                              ),
                                              const SizedBox(width: 6),

                                              /* OrdersToolbar.actionButton(
                                                  label:
                                                      'Items To Order (${s.itemsToOrder.length})',

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

                                                    if (!context.mounted) return;

                                                    context.read<OrdersBloc>().add(
                                                      const OrdersLoadItemsToOrder(),
                                                    );
                                                  },
                                                ),
                                                const SizedBox(width: 6),*/
                                              OrdersToolbar.actionButton(
                                                label:
                                                    'Send Additional ($draftAddCount)',
                                                icon: Icons.add_box_outlined,
                                                badgeCount: draftAddCount,
                                                color: AppColors.secondaryColor,
                                                onPressed:
                                                    (!zoneReady ||
                                                        s
                                                            .additionalEdits
                                                            .isEmpty ||
                                                        isBusy)
                                                    ? null
                                                    : () {
                                                        context
                                                            .read<OrdersBloc>()
                                                            .add(
                                                              OrdersSendAdditionalRequestsPressed(
                                                                zone: zs.zone!,
                                                              ),
                                                            );
                                                      },
                                              ),

                                              if (!s.isSubmitted &&
                                                  s.isOrderDay &&
                                                  OperationalDateHelper.canSubmitForBranch(
                                                    startHour:
                                                        s.submitStartHour,
                                                    endHour: s.submitEndHour,
                                                  ))
                                                const SizedBox(width: 6),

                                              if (!s.isSubmitted &&
                                                  s.isOrderDay &&
                                                  OperationalDateHelper.canSubmitForBranch(
                                                    startHour:
                                                        s.submitStartHour,
                                                    endHour: s.submitEndHour,
                                                  ))
                                                OrdersToolbar.actionButton(
                                                  label:
                                                      'Submit (${s.editsCount})',
                                                  icon: Icons
                                                      .check_circle_outline,
                                                  color:
                                                      AppColors.secondaryColor,
                                                  onPressed:
                                                      (!zoneReady ||
                                                          s.isSubmitted ||
                                                          isBusy ||
                                                          !s.isOrderDay ||
                                                          !OperationalDateHelper.canSubmitForBranch(
                                                            startHour: s
                                                                .submitStartHour,
                                                            endHour:
                                                                s.submitEndHour,
                                                          ))
                                                      ? null
                                                      : () async {
                                                          final bloc = context
                                                              .read<
                                                                OrdersBloc
                                                              >();

                                                          while (true) {
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
                                                                .isEmpty) {
                                                              break;
                                                            }

                                                            final result = await showDialog(
                                                              context: context,
                                                              barrierDismissible:
                                                                  false,
                                                              builder: (_) => PendingItemsToOrderDialog(
                                                                items:
                                                                    pendingItems,

                                                                onAddPressed: (item) async {
                                                                  final row = bloc
                                                                      .state
                                                                      .rows
                                                                      .firstWhere(
                                                                        (e) =>
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
                                                                      row.tmaQty
                                                                              .toString() !=
                                                                          '0';

                                                                  final edit =
                                                                      bloc
                                                                          .state
                                                                          .finalEdits[item
                                                                          .itemCode];

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
                                                                    final decision = await showDialog<String>(
                                                                      context:
                                                                          context,
                                                                      builder: (_) {
                                                                        return AlertDialog(
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
                                                                            TextButton(
                                                                              onPressed: () {
                                                                                Navigator.pop(
                                                                                  context,
                                                                                  'ignore',
                                                                                );
                                                                              },
                                                                              child: const Text(
                                                                                'Ignore',
                                                                              ),
                                                                            ),

                                                                            FilledButton(
                                                                              onPressed: () {
                                                                                Navigator.pop(
                                                                                  context,
                                                                                  'add',
                                                                                );
                                                                              },
                                                                              child: const Text(
                                                                                'Add Anyway',
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        );
                                                                      },
                                                                    );

                                                                    if (decision ==
                                                                        'ignore') {
                                                                      await bloc.repo.updateItemToOrderStatus(
                                                                        id: item
                                                                            .id,
                                                                        status:
                                                                            'ignored',
                                                                      );

                                                                      return false;
                                                                    }

                                                                    if (decision !=
                                                                        'add') {
                                                                      return false;
                                                                    }
                                                                  }

                                                                  // =========================
                                                                  // LIMITED STOCK
                                                                  // =========================

                                                                  final availableStock =
                                                                      (storeStock -
                                                                              totalReorderToday)
                                                                          .clamp(
                                                                            0,
                                                                            999999999,
                                                                          );

                                                                  final cap =
                                                                      oldQty +
                                                                      (availableStock *
                                                                              0.2)
                                                                          .floor();

                                                                  if (newQty >
                                                                      cap) {
                                                                    await showDialog(
                                                                      context:
                                                                          context,
                                                                      builder: (_) => LimitDialog(
                                                                        title:
                                                                            'Limited Stock',
                                                                        body:
                                                                            'Current Qty : $oldQty\n'
                                                                            'Requested Qty : $itemQty\n'
                                                                            'Max Allowed : $cap\n'
                                                                            'Final Qty : $newQty',
                                                                      ),
                                                                    );

                                                                    return false;
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

                                                                    return false;
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
                                                                    ),
                                                                  );

                                                                  await bloc.repo.upsertFinalReorderDraft(
                                                                    runDate: bloc
                                                                        .state
                                                                        .runDate,
                                                                    branchName: bloc
                                                                        .state
                                                                        .branchName,
                                                                    itemCode: item
                                                                        .itemCode,
                                                                    itemName: item
                                                                        .itemName,
                                                                    oldQty:
                                                                        oldQty,
                                                                    newQty:
                                                                        newQty,
                                                                    reason:
                                                                        'Items To Order',
                                                                  );

                                                                  await bloc
                                                                      .repo
                                                                      .updateItemToOrderStatus(
                                                                        id: item
                                                                            .id,
                                                                        status:
                                                                            'processed',
                                                                      );

                                                                  return true;
                                                                },
                                                              ),
                                                            );

                                                            if (result ==
                                                                null) {
                                                              return;
                                                            }

                                                            bloc.add(
                                                              const OrdersLoadItemsToOrder(),
                                                            );

                                                            await Future.delayed(
                                                              const Duration(
                                                                milliseconds:
                                                                    500,
                                                              ),
                                                            );
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
                                                                zone: zs.zone!,
                                                              );

                                                          if (confirmed !=
                                                              true) {
                                                            return;
                                                          }

                                                          if (!context.mounted)
                                                            return;

                                                          context
                                                              .read<
                                                                OrdersBloc
                                                              >()
                                                              .add(
                                                                OrdersSubmitOrderPressed(
                                                                  zone:
                                                                      zs.zone!,
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
                                          MediaQuery.of(context).size.height *
                                          0.4.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
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
                                                  s.categoryFilter != 'ALL' ||
                                                  s.formularyFilter != 'ALL' ||
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
                                                              FontWeight.w700,
                                                          color: Colors.black87,
                                                        ),
                                                      ),

                                                      const SizedBox(height: 8),

                                                      const Text(
                                                        'Current filters are hiding all items',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.grey,
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
                                                              Colors.redAccent,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 18,
                                                                vertical: 14,
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
                                                                    width: 8,
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
                                                orderedColumns: orderedColumns,
                                                columnWidths: s.columnWidths,
                                                finalEdits: s.finalEdits,
                                                submitStartHour:
                                                    s.submitStartHour,
                                                submitEndHour: s.submitEndHour,
                                                orderEditLimit:
                                                    s.orderEditLimit,

                                                onTapFinalReorder: (row) {
                                                  final locked =
                                                      s.isOrderDay &&
                                                      !s.isSubmitted &&
                                                      OperationalDateHelper.isMissingWindowForBranch(
                                                        startHour:
                                                            s.submitStartHour,
                                                        endHour:
                                                            s.submitEndHour,
                                                      );

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
                                                sentAdditionalQtyByItemCode: s
                                                    .sentAdditionalQtyByItemCode,
                                                onTapAdditionalRequest: (row) {
                                                  BranchOrdersActions.openAdditionalSidePanel(
                                                    context: context,
                                                    state: s,
                                                    row: row,
                                                  );
                                                },
                                                isSubmitted: s.isSubmitted,
                                                controller: _grid.controller,
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
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isSubmitted;
  final bool isOrderDay;
  final bool isMissingOrder;

  const _StatusChip({
    required this.isSubmitted,
    required this.isOrderDay,
    required this.isMissingOrder,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color br;
    Color fg;
    String text;
    IconData icon;

    if (!isOrderDay) {
      // 🔴 No Order Today
      bg = const Color(0xFFFFF1F2);
      br = const Color(0xFFFDA4AF);
      fg = const Color(0xFFB42318);
      text = 'No Order Today';
      icon = Icons.block;
    } else if (isSubmitted) {
      // ✅ Submitted
      bg = const Color(0xFFECFDF3);
      br = const Color(0xFFABEFC6);
      fg = const Color(0xFF027A48);
      text = 'Submitted';
      icon = Icons.check_circle;
    } else if (isMissingOrder) {
      // 🔥 Missing Order
      bg = const Color(0xFFFEF3F2);
      br = const Color(0xFFFDA29B);
      fg = const Color(0xFFB42318);
      text = 'Missing Order';
      icon = Icons.warning_amber_rounded;
    } else {
      // 🟡 Draft
      bg = const Color(0xFFFFFBEB);
      br = const Color(0xFFFDE68A);
      fg = const Color(0xFF92400E);
      text = 'Draft';
      icon = Icons.edit_outlined;
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
          Icon(
            isSubmitted ? Icons.check_circle : Icons.edit_outlined,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontWeight: FontWeight.w900, color: fg),
          ),
        ],
      ),
    );
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
                width: 80.w,
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
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w900,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
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
      padding: const EdgeInsets.all(14),
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

  /// 🔥 NEW
  final bool isSubmitted;

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

    /// 🔥 NEW
    required this.isSubmitted,

    required this.onAdditionalOnlyChanged,
    required this.onCategoryChanged,
    required this.onFormularyChanged,
    required this.onNonWithSales45Changed,
    this.onNumericFinalOnlyChanged,
    required this.receivedLast7DaysOnly,
    required this.onReceivedLast7DaysChanged,
    required this.onClearAll,
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

          itemWidth = 260.w;

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
                      'NEW ITEM',
                    ],
                    onChanged: onFormularyChanged,
                  ),
                ),*/
              SizedBox(
                width: itemWidth,
                child: _SwitchTile(
                  title: 'Item Received Last 7 Days',
                  subtitle: 'Show received items with stock > 0',
                  value: receivedLast7DaysOnly,
                  onChanged: onReceivedLast7DaysChanged,
                ),
              ),

              SizedBox(
                width: itemWidth,
                child: _SwitchTile(
                  title: 'NON + Sales (45d)',
                  subtitle: 'Show NON items with sales > 0',
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
                width: 140.w,
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
          vertical: 12,
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
        height: 56.h,
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
                      fontSize: 11.sp,
                      color: AppColors.secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.sp,
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
