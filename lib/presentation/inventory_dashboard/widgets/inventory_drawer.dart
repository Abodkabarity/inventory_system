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
  static const _trackerLastSeenKey = 'inventory_tracker_last_seen_at';
  DateTime? _trackerLastSeenAt;
  Future<void> _initTrackerBadge() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_trackerLastSeenKey);

    _trackerLastSeenAt = raw == null ? null : DateTime.tryParse(raw);

    await _loadTrackerCount();
  }

  Future<void> _markTrackerAsSeen() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_trackerLastSeenKey, now.toIso8601String());

    if (!mounted) return;

    setState(() {
      _trackerLastSeenAt = now;
      _trackerCount = 0;
    });
  }

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
        final from = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29));

        query = query.gte('changed_at', from.toIso8601String());
      }

      final res = await query;

      if (!mounted) return;

      setState(() {
        _trackerCount = (res as List).length;
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
        return Container(
          width: 270,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: 20,
                offset: const Offset(4, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              _Header(),

              const SizedBox(height: 18),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    children: [
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.dashboard,
                        icon: Icons.dashboard_rounded,
                        title: 'Dashboard',
                      ),
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.mismatch,
                        icon: Icons.warning_amber_rounded,
                        title: 'Mismatch Report',
                      ),
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.maxAdjustment,
                        icon: Icons.trending_up_rounded,
                        title: 'Max Adjustment',
                      ),
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.formulary,
                        icon: Icons.list_alt_rounded,
                        title: 'Formulary',
                      ),
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.assortment,
                        icon: Icons.category_rounded,
                        title: 'Assortment',
                      ),
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.dailyOrder,
                        icon: Icons.shopping_cart_rounded,
                        title: 'Daily Order',
                      ),
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.tma,
                        icon: Icons.medication_rounded,
                        title: 'TMA',
                      ),
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.additionalOrderAnalysis,
                        icon: Icons.analytics_rounded,
                        title: 'Additional Analysis',
                      ),
                      _menuItem(
                        context: context,
                        state: state,
                        page: InventoryPageType.branchesTracker,
                        icon: Icons.timeline_rounded,
                        title: 'Branches Tracker',
                        badgeCount: _trackerCount,
                        badgeLoading: _trackerLoading,
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

  Widget _menuItem({
    required BuildContext context,
    required InventoryState state,
    required InventoryPageType page,
    required IconData icon,
    required String title,
    int? badgeCount,
    bool badgeLoading = false,
  }) {
    final selected = state.currentPage == page;
    final showBadge = badgeLoading || ((badgeCount ?? 0) > 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          if (page == InventoryPageType.branchesTracker) {
            await _markTrackerAsSeen();
          }

          if (context.mounted) {
            context.read<InventoryBloc>().add(ChangeInventoryPage(page));
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      AppColors.primaryColor,
                      AppColors.primaryColor.withValues(alpha: .82),
                    ],
                  )
                : null,
            color: selected ? null : Colors.transparent,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primaryColor.withValues(alpha: .25),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : Colors.grey.shade700,
                size: 23,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : Colors.grey.shade800,
                  ),
                ),
              ),
              if (showBadge)
                _Badge(
                  count: badgeCount ?? 0,
                  loading: badgeLoading,
                  selected: selected,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 38, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 120,
              height: 70,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/logo1.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),
          Center(
            child: Text(
              'Inventory Management',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
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
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primaryColor,
        ),
      );
    }

    final text = count > 999 ? '999+' : count.toString();

    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withValues(alpha: .25) : Colors.red,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
