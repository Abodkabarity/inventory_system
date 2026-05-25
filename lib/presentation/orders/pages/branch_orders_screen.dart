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
import '../widgets/branch_zone_cubit.dart';
import '../widgets/orders_grid_controller.dart';
import '../widgets/orders_table.dart';
import '../widgets/orders_toolbar.dart';
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
                        color: Colors.black.withOpacity(.18),
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

                        const CircularProgressIndicator(),

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

                                    await Future.delayed(
                                      const Duration(milliseconds: 300),
                                    );

                                    bloc.add(const OrdersLoadAll());

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
        final sentAddCount = s.sentAdditionalQtyByItemCode.length;

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
                                  _StatusChip(
                                    isSubmitted: s.isSubmitted,
                                    isOrderDay: s.isOrderDay,

                                    isMissingOrder:
                                        s.isOrderDay &&
                                        !s.isSubmitted &&
                                        OperationalDateHelper
                                            .isMissingOrderWindow,
                                  ),
                                  const SizedBox(width: 10),
                                  _ZoneChip(zone: zs.zone),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 14),

                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (s.status == OrdersStatus.loading &&
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
                                            const CircularProgressIndicator(),

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

                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      SizedBox(
                                        width: 300.w,
                                        height: 75.h,
                                        child: _KpiCard(
                                          title: 'Total Products',
                                          value: statsAll.totalProducts
                                              .toString(),
                                          subtitle: 'All APG Items',
                                          icon: Icons.list_alt_outlined,
                                        ),
                                      ),

                                      SizedBox(
                                        width: 300.w,
                                        height: 75.h,
                                        child: _KpiCard(
                                          title: 'Items in Order',
                                          value: statsAll.finalReorderCount
                                              .round()
                                              .toString(),
                                          subtitle: '',
                                          icon: Icons.inventory_2_outlined,
                                        ),
                                      ),

                                      SizedBox(
                                        width: 300.w,
                                        height: 75.h,
                                        child: _KpiCard(
                                          title: 'Essential',
                                          value: '${statsAll.essential}',
                                          subtitle: '',
                                          icon: Icons.star_border,
                                        ),
                                      ),

                                      SizedBox(
                                        width: 300.w,
                                        height: 75.h,
                                        child: _KpiCard(
                                          title: 'Non',
                                          value: '${statsAll.non}',
                                          subtitle: '',
                                          icon: Icons.layers_outlined,
                                        ),
                                      ),

                                      SizedBox(
                                        width: 300.w,
                                        height: 75.h,
                                        child: _KpiCard(
                                          title: 'Additional Orders Today',
                                          value: '$sentAddCount',
                                          subtitle: '',
                                          icon: Icons.add_box_outlined,
                                        ),
                                      ),
                                    ],
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
                                                  OperationalDateHelper
                                                      .canSubmit)
                                                const SizedBox(width: 6),

                                              if (!s.isSubmitted &&
                                                  s.isOrderDay &&
                                                  OperationalDateHelper
                                                      .canSubmit)
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
                                                          !OperationalDateHelper
                                                              .canSubmit)
                                                      ? null
                                                      : () async {
                                                          // 🔥 OPEN REVIEW FIRST
                                                          final confirmed =
                                                              await BranchOrdersActions.openSubmitReviewDialog(
                                                                context:
                                                                    context,
                                                                state: s,
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
                                                onTapFinalReorder: (row) {
                                                  final locked =
                                                      s.isOrderDay &&
                                                      !s.isSubmitted &&
                                                      OperationalDateHelper
                                                          .isMissingOrderWindow;

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
                width: 100.w,
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
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
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

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 98,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8F0)),
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
            child: Icon(icon, color: AppColors.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
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
                        style: const TextStyle(
                          fontSize: 12,
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
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModernDropdown(
              label: 'Category',
              value: selectedCategory,
              items: categories,
              onChanged: onCategoryChanged,
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: _ModernDropdown(
              label: 'Formulary',
              value: selectedFormulary,
              items: const [
                'ALL',
                'ESSENTIAL',
                'NON',
                "SALES",
                "TMA",
                "NEW ITEM",
              ],
              onChanged: onFormularyChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SwitchTile(
              title: 'Item Received Last 7 Days',
              subtitle: 'Show received items with stock > 0',
              value: receivedLast7DaysOnly,
              onChanged: onReceivedLast7DaysChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SwitchTile(
              title: 'NON + Sales (45d)',
              subtitle: 'Show NON items with sales > 0',
              value: nonWithSales45Only,
              onChanged: onNonWithSales45Changed,
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: _SwitchTile(
              title: 'Available Item in Order',
              subtitle: '',
              value: numericFinalOnly,

              onChanged: onNumericFinalOnlyChanged,
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: _SwitchTile(
              title: 'Additional Only',
              subtitle: 'Show items with additional requests',
              value: additionalOnly,
              onChanged: onAdditionalOnlyChanged,
            ),
          ),
        ],
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
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWidget,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8F0)),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: AppColors.secondaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF6B7280),
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
