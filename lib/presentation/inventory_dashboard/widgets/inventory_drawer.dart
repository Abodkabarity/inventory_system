import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/inventory_page.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';

class InventoryDrawer extends StatefulWidget {
  const InventoryDrawer({super.key});

  @override
  State<InventoryDrawer> createState() => _InventoryDrawerState();
}

class _InventoryDrawerState extends State<InventoryDrawer> {
  int _trackerCount = 0;
  bool _trackerLoading = true;

  RealtimeChannel? _trackerChannel;
  DateTime? _trackerLastSeenAt;

  bool _orderManagementExpanded = true;
  bool _operationsExpanded = true;
  bool _analyticsExpanded = true;
  bool _configurationExpanded = true;

  static const String _trackerLastSeenKey = 'inventory_tracker_last_seen_at';

  static const Set<InventoryPageType> _orderManagementPages = {
    InventoryPageType.dailyOrder,
    InventoryPageType.maxAdjustment,
    InventoryPageType.formulary,
    InventoryPageType.assortment,
    InventoryPageType.tma,
  };

  static const Set<InventoryPageType> _operationsPages = {
    InventoryPageType.additionalOrders,
    InventoryPageType.itemsTracker,
    InventoryPageType.allocation,
    InventoryPageType.stockCheck,
    InventoryPageType.branchSubmissionTracker,
    InventoryPageType.branchesTracker,
  };

  static const Set<InventoryPageType> _analyticsPages = {
    InventoryPageType.mismatch,
    InventoryPageType.additionalOrderAnalysis,
    InventoryPageType.orderEditAnalysis,
    InventoryPageType.shortage,
    InventoryPageType.availabilityKpi,
    InventoryPageType.fillRateKpi,
  };

  static const Set<InventoryPageType> _configurationPages = {
    InventoryPageType.branchSetting,
  };

  @override
  void initState() {
    super.initState();

    _initTrackerBadge();
    _startTrackerRealtime();
  }

  @override
  void dispose() {
    if (_trackerChannel != null) {
      Supabase.instance.client.removeChannel(_trackerChannel!);
    }

    super.dispose();
  }

  Future<void> _initTrackerBadge() async {
    final preferences = await SharedPreferences.getInstance();
    final savedValue = preferences.getString(_trackerLastSeenKey);

    _trackerLastSeenAt = savedValue == null
        ? null
        : DateTime.tryParse(savedValue);

    await _loadTrackerCount();
  }

  Future<void> _markTrackerAsSeen() async {
    final now = DateTime.now();
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(_trackerLastSeenKey, now.toIso8601String());

    if (!mounted) return;

    setState(() {
      _trackerLastSeenAt = now;
      _trackerCount = 0;
    });
  }

  Future<void> _loadTrackerCount() async {
    try {
      final since = _trackerLastSeenAt;

      var query = Supabase.instance.client
          .from('branch_change_tracker')
          .select('source_id');

      if (since != null) {
        query = query.gt('changed_at', since.toIso8601String());
      } else {
        final now = DateTime.now();

        final fromDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29));

        query = query.gte('changed_at', fromDate.toIso8601String());
      }

      final response = await query;

      if (!mounted) return;

      setState(() {
        _trackerCount = (response as List).length;
        _trackerLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _trackerCount = 0;
        _trackerLoading = false;
      });
    }
  }

  void _startTrackerRealtime() {
    final client = Supabase.instance.client;

    _trackerChannel = client
        .channel('inventory-drawer-branches-tracker')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_edits',
          callback: (_) => _loadTrackerCount(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'max_adj',
          callback: (_) => _loadTrackerCount(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'max_adj_log',
          callback: (_) => _loadTrackerCount(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mismatch_log',
          callback: (_) => _loadTrackerCount(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stk_mismatch',
          callback: (_) => _loadTrackerCount(),
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        final currentPage = state.currentPage;

        return Container(
          width: 290,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(4, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              const _Header(),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.dashboard,
                        icon: Icons.dashboard_rounded,
                        title: 'Dashboard',
                        standalone: true,
                      ),

                      const SizedBox(height: 14),

                      _drawerSection(
                        title: 'ORDER MANAGEMENT',
                        icon: Icons.shopping_cart_checkout_rounded,
                        expanded: _orderManagementExpanded,
                        active: _orderManagementPages.contains(currentPage),
                        onToggle: () {
                          setState(() {
                            _orderManagementExpanded =
                                !_orderManagementExpanded;
                          });
                        },
                        children: [
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.dailyOrder,
                            icon: Icons.shopping_cart_rounded,
                            title: 'Daily Order',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.maxAdjustment,
                            icon: Icons.trending_up_rounded,
                            title: 'Max Adjustment',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.formulary,
                            icon: Icons.list_alt_rounded,
                            title: 'Formulary',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.assortment,
                            icon: Icons.category_rounded,
                            title: 'Assortment',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.tma,
                            icon: Icons.medication_rounded,
                            title: 'TMA',
                            nested: true,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      _drawerSection(
                        title: 'OPERATIONS',
                        icon: Icons.settings_suggest_rounded,
                        expanded: _operationsExpanded,
                        active: _operationsPages.contains(currentPage),
                        onToggle: () {
                          setState(() {
                            _operationsExpanded = !_operationsExpanded;
                          });
                        },
                        children: [
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.additionalOrders,
                            icon: Icons.add_shopping_cart_rounded,
                            title: 'Additional Orders',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.itemsTracker,
                            icon: Icons.track_changes_rounded,
                            title: 'Items Tracker',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.allocation,
                            icon: Icons.account_tree_rounded,
                            title: 'Allocation',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.stockCheck,
                            icon: Icons.inventory_2_rounded,
                            title: 'Stock Check',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.shortage,
                            icon: Icons.production_quantity_limits_rounded,
                            title: 'Shortage',
                            nested: true,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      _drawerSection(
                        title: 'ANALYTICS & REPORTS',
                        icon: Icons.analytics_rounded,
                        expanded: _analyticsExpanded,
                        active: _analyticsPages.contains(currentPage),
                        onToggle: () {
                          setState(() {
                            _analyticsExpanded = !_analyticsExpanded;
                          });
                        },
                        children: [
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.branchSubmissionTracker,
                            icon: Icons.assignment_late_rounded,
                            title: 'Submission Tracker',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.branchesTracker,
                            icon: Icons.timeline_rounded,
                            title: 'Branches Tracker',
                            badgeCount: _trackerCount,
                            badgeLoading: _trackerLoading,
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.mismatch,
                            icon: Icons.warning_amber_rounded,
                            title: 'Mismatch Report',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.additionalOrderAnalysis,
                            icon: Icons.bar_chart_rounded,
                            title: 'Additional Analysis',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.orderEditAnalysis,
                            icon: Icons.add_chart_rounded,
                            title: 'Order Edit Analysis',
                            nested: true,
                          ),

                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.availabilityKpi,
                            icon: Icons.monitor_heart_rounded,
                            title: 'Availability KPI',
                            nested: true,
                          ),
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.fillRateKpi,
                            icon: Icons.local_shipping_rounded,
                            title: 'Fill Rate KPI',
                            nested: true,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      _drawerSection(
                        title: 'CONFIGURATION',
                        icon: Icons.tune_rounded,
                        expanded: _configurationExpanded,
                        active: _configurationPages.contains(currentPage),
                        onToggle: () {
                          setState(() {
                            _configurationExpanded = !_configurationExpanded;
                          });
                        },
                        children: [
                          _menuItem(
                            context: context,
                            state: state,
                            page: InventoryPageType.branchSetting,
                            icon: Icons.store_rounded,
                            title: 'Branch Setting',
                            nested: true,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      const _DrawerFooter(),
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

  Widget _drawerSection({
    required String title,
    required IconData icon,
    required bool expanded,
    required bool active,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: active
            ? AppColors.primaryColor.withValues(alpha: 0.055)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? AppColors.primaryColor.withValues(alpha: 0.20)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primaryColor.withValues(alpha: 0.12)
                            : const Color(0xFFF1F4F8),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: active
                            ? AppColors.primaryColor
                            : const Color(0xFF596273),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: active
                              ? AppColors.primaryColor
                              : const Color(0xFF3B4657),
                        ),
                      ),
                    ),

                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 24,
                        color: active
                            ? AppColors.primaryColor
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: expanded
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Divider(height: 1, color: Colors.grey.shade200),
                      ),

                      const SizedBox(height: 6),

                      ...children,

                      const SizedBox(height: 8),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required BuildContext context,
    required InventoryState state,
    required InventoryPageType page,
    required IconData icon,
    required String title,
    int? badgeCount,
    bool badgeLoading = false,
    bool nested = false,
    bool standalone = false,
  }) {
    final selected = state.currentPage == page;
    final showBadge = badgeLoading || ((badgeCount ?? 0) > 0);

    final horizontalPadding = standalone ? 2.0 : 8.0;
    final verticalPadding = standalone ? 3.0 : 2.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () async {
            if (page == InventoryPageType.branchesTracker) {
              await _markTrackerAsSeen();
            }

            if (!context.mounted) return;

            context.read<InventoryBloc>().add(ChangeInventoryPage(page));
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 230),
            curve: Curves.easeInOut,
            padding: EdgeInsets.symmetric(
              horizontal: nested ? 13 : 18,
              vertical: standalone ? 15 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(standalone ? 17 : 14),
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.primaryColor,
                        AppColors.primaryColor.withValues(alpha: 0.82),
                      ],
                    )
                  : null,
              color: selected ? null : Colors.transparent,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primaryColor.withValues(alpha: 0.23),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 230),
                  width: standalone ? 38 : 34,
                  height: standalone ? 38 : 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.18)
                        : nested
                        ? const Color(0xFFF1F4F8)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: standalone ? 21 : 19,
                    color: selected ? Colors.white : const Color(0xFF586273),
                  ),
                ),

                SizedBox(width: standalone ? 12 : 10),

                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: standalone ? 15.5 : 14.3,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF303846),
                    ),
                  ),
                ),

                if (showBadge) ...[
                  const SizedBox(width: 8),
                  _Badge(
                    count: badgeCount ?? 0,
                    loading: badgeLoading,
                    selected: selected,
                  ),
                ],

                if (selected && !showBadge) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Container(
            width: 122,
            height: 68,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/logo1.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Inventory Management',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            'Daily Order System',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryColor.withValues(alpha: 0.08),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppColors.primaryColor,
              size: 21,
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Inventory Control',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF263244),
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  'Data • Accuracy • Availability',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
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

class _Badge extends StatelessWidget {
  final int count;
  final bool loading;
  final bool selected;

  const _Badge({
    required this.count,
    required this.loading,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        width: 17,
        height: 17,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: selected ? Colors.white : AppColors.primaryColor,
        ),
      );
    }

    final text = count > 999 ? '999+' : count.toString();

    return Container(
      constraints: const BoxConstraints(minWidth: 26, minHeight: 23),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.24)
            : const Color(0xFFE5484D),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
