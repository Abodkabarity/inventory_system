// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, unused_element

import 'dart:async';
import 'dart:html' as html;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/stock_check_excel_exporter.dart';
import '../../../data/datasources/remote/orders_remote_ds.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../../../domain/entities/stock_check_task.dart';
import '../../inventory_dashboard/page/additional_order_analysis_page.dart'
    show AdditionalAnalysisDateRangePickerDialog;
import '../../orders/widgets/orders_grid_controller.dart';
import '../../orders/widgets/orders_table.dart';

part 'pages/zone_additional_orders_page.dart';
part 'pages/zone_daily_order_history_page.dart';
part 'pages/zone_daily_order_page.dart';
part 'pages/zone_dashboard_page.dart';
part 'pages/zone_handover_page.dart';
part 'pages/zone_max_adjustment_page.dart';
part 'pages/zone_mismatch_page.dart';
part 'pages/zone_non_received_page.dart';
part 'pages/zone_order_edits_page.dart';
part 'pages/zone_stock_check_page.dart';

class ZoneManagerPage extends StatefulWidget {
  final String runDate;
  final List<String> zoneNames;

  String get zoneName => zoneNames.join(' + ');

  const ZoneManagerPage({
    super.key,
    required this.runDate,
    required this.zoneNames,
  });

  @override
  State<ZoneManagerPage> createState() => _ZoneManagerPageState();
}

class _ZoneManagerPageState extends State<ZoneManagerPage> {
  final _client = Supabase.instance.client;
  final _search = TextEditingController();
  final _dailyGridController = OrdersGridController();

  bool _loading = true;
  bool _drawerCollapsed = false;
  bool _busy = false;
  bool _reportLoading = false;
  String? _error;
  int _page = 0;
  String _selectedBranch = 'ALL';
  String _query = '';

  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _dailyRawRows = const [];
  List<DailyOrderRow> _dailyRows = const [];
  bool _dailyLoading = false;
  String? _dailyError;
  String _dailyRequestKey = '';
  int _dailyRequestId = 0;
  // Kept for the retired paginated widget below; it is no longer routed.
  List<Map<String, dynamic>> get _dailyPageRows => _dailyRawRows;
  final Map<String, double> _dailyColumnWidths = {
    'row_no': 64,
    'item_code': 145,
    'item_name': 310,
    'branch_stock': 135,
    'mismatch_stock': 145,
    'store_stock': 125,
    'pending_stock_received': 165,
    'demand_for_30_days': 145,
    'reorder_point_min': 145,
    'reorder_max': 130,
    'reorder_qty': 135,
    'final_reorder_qty_store_stock_gt_0': 190,
    'category': 170,
    'barcode': 170,
  };
  List<Map<String, dynamic>> _additional = const [];
  List<Map<String, dynamic>> _additionalReport = const [];
  late DateTime _additionalFrom;
  late DateTime _additionalTo;
  bool _additionalReportLoading = false;
  List<Map<String, dynamic>> _mismatch = const [];
  List<Map<String, dynamic>> _maxAdj = const [];
  Map<String, Map<String, dynamic>> _maxCredits = const {};
  List<Map<String, dynamic>> _dailyExports = const [];
  List<Map<String, dynamic>> _nonReceivedExports = const [];
  List<Map<String, dynamic>> _edits = const [];
  List<Map<String, dynamic>> _editsReport = const [];
  late DateTime _editsFrom;
  late DateTime _editsTo;
  bool _editsReportLoading = false;
  List<StockCheckTask> _stockChecks = const [];
  List<StockCheckTask> _dashboardStockChecks = const [];
  bool _stockCheckLoading = false;
  String? _stockCheckError;
  String? _selectedStockCheckBatchId;
  Map<String, Map<String, dynamic>> _submissions = const {};
  List<_ZoneLiveActivity> _liveActivities = const [];
  List<String> _effectiveZones = const [];
  List<String> _permanentZones = const [];
  List<Map<String, dynamic>> _zoneDelegations = const [];
  List<Map<String, dynamic>> _zoneManagerDirectory = const [];
  String _currentZoneManagerName = 'Zone Manager';
  bool _handoverAvailable = true;
  bool _handoverBusy = false;
  bool _handoverContextLoading = false;
  RealtimeChannel? _zoneActivityChannel;
  RealtimeChannel? _delegationChannel;
  Timer? _dashboardClock;
  Timer? _stockCheckRealtimeDebounce;
  Timer? _delegationRealtimeDebounce;
  Timer? _delegationClock;
  StreamSubscription<html.Event>? _dashboardFocusSubscription;
  bool _dashboardStockCheckSyncing = false;
  int _dashboardStockCheckClockMinute = -1;
  Set<String> _zoneActivityBranchKeys = const {};
  bool _liveActivityConnected = false;

  String get _zoneLabel =>
      _effectiveZones.isEmpty ? widget.zoneName : _effectiveZones.join(' + ');

  void _setBusy(bool value) {
    if (mounted) setState(() => _busy = value);
  }

  void _selectStockCheckBatch(String? batchId) {
    if (mounted) setState(() => _selectedStockCheckBatchId = batchId);
  }

  static const _pages = [
    _PageDef(Icons.dashboard_rounded, 'Dashboard'),
    _PageDef(Icons.warning_amber_rounded, 'Mismatch Report'),
    _PageDef(Icons.trending_up_rounded, 'Max Adjustment'),
    _PageDef(Icons.shopping_cart_rounded, 'Daily Order'),
    _PageDef(Icons.send_to_mobile_rounded, 'Additional Orders'),
    _PageDef(Icons.edit_note_rounded, 'Order Edits'),
    _PageDef(Icons.fact_check_outlined, 'Stock Check'),
    _PageDef(Icons.inventory_2_outlined, 'Non Received'),
    _PageDef(Icons.download_rounded, 'Daily Order History'),
    _PageDef(Icons.handshake_outlined, 'Zone Handover'),
  ];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _effectiveZones = List<String>.from(widget.zoneNames);
    _permanentZones = List<String>.from(widget.zoneNames);
    _additionalFrom = DateTime(today.year, today.month, today.day);
    _additionalTo = DateTime(today.year, today.month, today.day, 23, 59, 59);
    _editsFrom = DateTime(today.year, today.month, today.day);
    _editsTo = DateTime(today.year, today.month, today.day, 23, 59, 59);
    _dashboardClock = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _page != 0) return;
      unawaited(_refreshDashboardStockChecks());
    });
    _dashboardFocusSubscription = html.window.onFocus.listen((_) {
      if (mounted && _page == 0) {
        unawaited(_refreshDashboardStockChecks());
        unawaited(_refreshDelegationContext());
      }
    });
    _delegationClock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) unawaited(_refreshDelegationContext());
    });
    _load();
  }

  @override
  void dispose() {
    _dashboardClock?.cancel();
    _stockCheckRealtimeDebounce?.cancel();
    _delegationRealtimeDebounce?.cancel();
    _delegationClock?.cancel();
    _dashboardFocusSubscription?.cancel();
    final activityChannel = _zoneActivityChannel;
    if (activityChannel != null) {
      _client.removeChannel(activityChannel);
    }
    final delegationChannel = _delegationChannel;
    if (delegationChannel != null) {
      _client.removeChannel(delegationChannel);
    }
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final zoneContext = await _loadZoneContext();
      final activeZones = zoneContext.effectiveZones.isEmpty
          ? List<String>.from(widget.zoneNames)
          : zoneContext.effectiveZones;
      final branchData = await _client
          .from('branches')
          .select('branch_name,zone,submit_end_hour,max_adj_limit')
          .eq('is_active', true)
          .inFilter('zone', activeZones)
          .order('branch_name');
      final branches = List<Map<String, dynamic>>.from(branchData);
      branches.sort(
        (left, right) => _text(
          left['branch_name'],
        ).toLowerCase().compareTo(_text(right['branch_name']).toLowerCase()),
      );
      final names = branches
          .map((row) => _text(row['branch_name']))
          .where((name) => name.isNotEmpty)
          .toList();

      final result = await Future.wait<dynamic>([
        _loadAdditional(names),
        _loadDailyExports(names),
        _loadNonReceivedExports(names),
        _loadEdits(names),
        _loadSubmissions(names),
        _loadRecentZoneActivity(names),
        _loadMaxCredits(names),
        _loadDashboardStockChecks(names),
        _loadAdditionalRange(names, _additionalFrom, _additionalTo),
      ]);
      final editsReport =
          _dateKey(_editsFrom) == widget.runDate &&
              _dateKey(_editsTo) == widget.runDate
          ? List<Map<String, dynamic>>.from(result[3])
          : await _loadEditsRange(names, _editsFrom, _editsTo);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _additional = result[0];
        _dailyExports = result[1];
        _nonReceivedExports = result[2];
        _edits = result[3];
        _editsReport = editsReport;
        _submissions = result[4];
        _liveActivities = result[5];
        _maxCredits = result[6];
        _dashboardStockChecks = result[7];
        _additionalReport = result[8];
        _effectiveZones = activeZones;
        _permanentZones = zoneContext.permanentZones;
        _zoneDelegations = zoneContext.delegations;
        _zoneManagerDirectory = zoneContext.directory;
        _currentZoneManagerName = zoneContext.currentUserName;
        _handoverAvailable = zoneContext.handoverAvailable;
        if (_selectedBranch != 'ALL' && !names.contains(_selectedBranch)) {
          _selectedBranch = 'ALL';
        }
        _loading = false;
      });
      _subscribeToZoneActivity(names);
      _subscribeToDelegations();
      if (_page == 3) await _loadDailyBranch();
      if (_page == 6) await _loadStockChecks();
      if (_page == 1 || _page == 2) {
        await _loadZoneReport(_page, force: true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<_ZoneContextData> _loadZoneContext() async {
    final uid = _client.auth.currentUser?.id ?? '';
    final effective = <String>{...widget.zoneNames};
    final permanent = <String>{...widget.zoneNames};
    var delegations = <Map<String, dynamic>>[];
    var directory = <Map<String, dynamic>>[];
    var currentName =
        _client.auth.currentUser?.email?.split('@').first.trim() ??
        'Zone Manager';
    var handoverAvailable = true;

    if (uid.isEmpty) {
      return _ZoneContextData(
        effectiveZones: effective.toList()..sort(),
        permanentZones: permanent.toList()..sort(),
        delegations: const [],
        directory: const [],
        currentUserName: currentName,
        handoverAvailable: false,
      );
    }

    try {
      final rows = List<Map<String, dynamic>>.from(
        await _client.rpc('get_my_effective_zones'),
      );
      effective.clear();
      permanent.clear();
      for (final row in rows) {
        final zone = _text(row['zone']);
        if (zone.isEmpty) continue;
        effective.add(zone);
        if (_text(row['assignment_kind']).toLowerCase() == 'permanent') {
          permanent.add(zone);
        }
      }
    } catch (error) {
      debugPrint('Effective zone RPC fallback: $error');
      try {
        final rows = List<Map<String, dynamic>>.from(
          await _client
              .from('app_user_zones')
              .select('zone')
              .eq('user_id', uid),
        );
        for (final row in rows) {
          final zone = _text(row['zone']);
          if (zone.isNotEmpty) {
            effective.add(zone);
            permanent.add(zone);
          }
        }
      } catch (_) {
        handoverAvailable = false;
      }
    }

    try {
      directory = List<Map<String, dynamic>>.from(
        await _client.rpc('get_zone_manager_directory'),
      );
      delegations = List<Map<String, dynamic>>.from(
        await _client
            .from('zone_management_delegations')
            .select()
            .or('requester_user_id.eq.$uid,recipient_user_id.eq.$uid')
            .order('created_at', ascending: false)
            .limit(200),
      );
    } catch (error) {
      debugPrint('Zone handover module unavailable: $error');
      handoverAvailable = false;
    }

    try {
      final profile = await _client
          .from('app_users')
          .select('user_name')
          .eq('user_id', uid)
          .maybeSingle();
      final profileName = _text(profile?['user_name']);
      if (profileName.isNotEmpty) currentName = profileName;
    } catch (_) {
      // Email prefix remains a safe display fallback.
    }

    final effectiveList = effective.where((zone) => zone.isNotEmpty).toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    final permanentList = permanent.where((zone) => zone.isNotEmpty).toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    return _ZoneContextData(
      effectiveZones: effectiveList,
      permanentZones: permanentList,
      delegations: delegations,
      directory: directory,
      currentUserName: currentName,
      handoverAvailable: handoverAvailable,
    );
  }

  Future<void> _refreshDelegationContext() async {
    if (_handoverContextLoading || !mounted) return;
    _handoverContextLoading = true;
    try {
      final contextData = await _loadZoneContext();
      if (!mounted) return;
      if (!_sameZoneSet(_effectiveZones, contextData.effectiveZones)) {
        await _load();
        return;
      }
      setState(() {
        _permanentZones = contextData.permanentZones;
        _zoneDelegations = contextData.delegations;
        _zoneManagerDirectory = contextData.directory;
        _currentZoneManagerName = contextData.currentUserName;
        _handoverAvailable = contextData.handoverAvailable;
      });
    } finally {
      _handoverContextLoading = false;
    }
  }

  bool _sameZoneSet(List<String> left, List<String> right) {
    final leftKeys = left.map(_key).toSet();
    final rightKeys = right.map(_key).toSet();
    return leftKeys.length == rightKeys.length &&
        leftKeys.containsAll(rightKeys);
  }

  List<String> _delegationZones(dynamic value) {
    if (value is List) {
      return value
          .map((zone) => _text(zone))
          .where((zone) => zone.isNotEmpty)
          .toList(growable: false);
    }
    final text = _text(value).replaceAll(RegExp(r'[{}\[\]"]'), '');
    return text
        .split(',')
        .map((zone) => zone.trim())
        .where((zone) => zone.isNotEmpty)
        .toList(growable: false);
  }

  String _zoneManagerName(String userId) {
    final uid = _client.auth.currentUser?.id ?? '';
    if (userId == uid) return _currentZoneManagerName;
    for (final row in _zoneManagerDirectory) {
      if (_text(row['user_id']) == userId) {
        final name = _text(row['user_name']);
        if (name.isNotEmpty) return name;
      }
    }
    return 'Zone Manager';
  }

  Future<bool> _createZoneHandover({
    required String recipientUserId,
    required List<String> zones,
    required DateTime startAt,
    required DateTime endAt,
    required String reason,
  }) async {
    if (_handoverBusy) return false;
    setState(() => _handoverBusy = true);
    try {
      await _client.rpc(
        'create_zone_delegation',
        params: {
          'p_recipient_user_id': recipientUserId,
          'p_zones': zones,
          'p_start_at': startAt.toUtc().toIso8601String(),
          'p_end_at': endAt.toUtc().toIso8601String(),
          'p_reason': reason.trim(),
        },
      );
      if (!mounted) return false;
      _message('Zone handover request sent successfully.');
      await _refreshDelegationContext();
      return true;
    } catch (error) {
      if (mounted) _message('Could not send handover: $error', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _handoverBusy = false);
    }
  }

  Future<void> _respondToZoneHandover(String id, bool accept) async {
    if (_handoverBusy) return;
    if (!accept) {
      final row = _zoneDelegations
          .where((item) => _text(item['id']) == id)
          .firstOrNull;
      final confirmed = await _showZoneHandoverConfirmation(
        action: _ZoneHandoverConfirmAction.decline,
        row: row,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _handoverBusy = true);
    try {
      await _client.rpc(
        'respond_zone_delegation',
        params: {'p_delegation_id': id, 'p_accept': accept},
      );
      if (!mounted) return;
      _message(accept ? 'Handover accepted.' : 'Handover declined.');
      await _refreshDelegationContext();
    } catch (error) {
      if (mounted) _message('Could not respond: $error', error: true);
    } finally {
      if (mounted) setState(() => _handoverBusy = false);
    }
  }

  Future<void> _cancelZoneHandover(String id) async {
    if (_handoverBusy) return;
    final row = _zoneDelegations
        .where((item) => _text(item['id']) == id)
        .firstOrNull;
    final confirmed = await _showZoneHandoverConfirmation(
      action: _ZoneHandoverConfirmAction.cancel,
      row: row,
    );
    if (!confirmed || !mounted) return;
    setState(() => _handoverBusy = true);
    try {
      await _client.rpc(
        'cancel_zone_delegation',
        params: {'p_delegation_id': id},
      );
      if (!mounted) return;
      _message('Handover cancelled.');
      await _refreshDelegationContext();
    } catch (error) {
      if (mounted) _message('Could not cancel: $error', error: true);
    } finally {
      if (mounted) setState(() => _handoverBusy = false);
    }
  }

  Future<void> _loadDailyBranch() async {
    final requestId = ++_dailyRequestId;
    if (_selectedBranch == 'ALL' || _selectedBranch.isEmpty) {
      if (mounted) {
        setState(() {
          _dailyRawRows = const [];
          _dailyRows = const [];
          _dailyError = null;
        });
      }
      return;
    }
    final requestKey = '$_selectedBranch|${widget.runDate}';
    setState(() {
      _dailyLoading = true;
      _dailyError = null;
    });
    try {
      final rawRows = await OrdersRemoteDs(
        _client,
      ).fetchOrdersAll(runDate: widget.runDate, branchName: _selectedBranch);
      if (!mounted || requestId != _dailyRequestId) return;
      setState(() {
        _dailyRawRows = rawRows;
        _dailyRows = rawRows.map(DailyOrderRow.fromMap).toList(growable: false);
        _dailyRequestKey = requestKey;
      });
    } catch (error) {
      if (!mounted || requestId != _dailyRequestId) return;
      setState(() => _dailyError = error.toString());
    } finally {
      if (mounted && requestId == _dailyRequestId) {
        setState(() => _dailyLoading = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAdditional(
    List<String> branches,
  ) => _fetchByBranch(
    table: 'additional_requests',
    branchColumn: 'branch_name',
    branches: branches,
    columns:
        'id,run_date,branch_name,item_code,item_name,status,request_qty,inventory_qty,fulfilled_qty,branch_stock,store_stock,sales_45d,final_reorder_qty,item_purchase_type,inventory_note,store_note,created_at,inventory_approved_at,done_at',
    runDateColumn: 'run_date',
    orderBy: 'created_at',
  );

  Future<List<Map<String, dynamic>>> _loadAdditionalRange(
    List<String> branches,
    DateTime from,
    DateTime to,
  ) async {
    if (branches.isEmpty) return const [];
    final output = <Map<String, dynamic>>[];
    final fromDate = _dateKey(from);
    final toDate = _dateKey(to);
    for (final chunk in _chunks(branches, 20)) {
      var offset = 0;
      const batchSize = 500;
      while (true) {
        final rows = List<Map<String, dynamic>>.from(
          await _client
              .from('additional_requests')
              .select(
                'id,run_date,branch_name,item_code,item_name,status,request_qty,inventory_qty,fulfilled_qty,branch_stock,store_stock,sales_45d,final_reorder_qty,item_purchase_type,inventory_note,store_note,created_at,inventory_approved_at,done_at',
              )
              .inFilter('branch_name', chunk)
              .gte('run_date', fromDate)
              .lte('run_date', toDate)
              .order('created_at', ascending: false)
              .range(offset, offset + batchSize - 1),
        );
        if (rows.isEmpty) break;
        output.addAll(rows);
        offset += rows.length;
      }
    }
    return output;
  }

  Future<void> _reloadAdditionalReport() async {
    if (_additionalReportLoading || !mounted) return;
    final branches = _branches
        .map((row) => _text(row['branch_name']))
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    setState(() => _additionalReportLoading = true);
    try {
      final rows = await _loadAdditionalRange(
        branches,
        _additionalFrom,
        _additionalTo,
      );
      if (!mounted) return;
      setState(() => _additionalReport = rows);
    } catch (error) {
      if (mounted) {
        _message('Could not load Additional Orders: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _additionalReportLoading = false);
    }
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool _additionalRangeContains(dynamic value) {
    final date = DateTime.tryParse(_text(value));
    if (date == null) return false;
    final day = DateTime(date.year, date.month, date.day);
    final from = DateTime(
      _additionalFrom.year,
      _additionalFrom.month,
      _additionalFrom.day,
    );
    final to = DateTime(
      _additionalTo.year,
      _additionalTo.month,
      _additionalTo.day,
    );
    return !day.isBefore(from) && !day.isAfter(to);
  }

  Future<List<Map<String, dynamic>>> _loadMismatch(
    List<String> branches,
  ) => _fetchByBranch(
    table: 'stk_mismatch',
    branchColumn: 'branch_name',
    branches: branches,
    columns:
        'id,branch_name,item_code,item_name,system_stock,actual_stock,diff,update_date,created_at',
    orderBy: 'update_date',
    tieBreaker: 'id',
  );

  Future<List<Map<String, dynamic>>> _loadMaxAdj(
    List<String> branches,
  ) => _fetchByBranch(
    table: 'max_adj',
    branchColumn: 'branch_name',
    branches: branches,
    columns:
        'id,branch_name,item_code,item_name,current_demand_30d,max_adjustment_30d,adjustment_type,qty,reason,update_date,added_by,created_at,end_date',
    orderBy: 'created_at',
    tieBreaker: 'id',
  );

  Future<Map<String, Map<String, dynamic>>> _loadMaxCredits(
    List<String> branches,
  ) async {
    final output = <String, Map<String, dynamic>>{};
    for (final chunk in _chunks(branches, 20)) {
      try {
        final rows = List<Map<String, dynamic>>.from(
          await _client
              .from('vw_max_adj_usage')
              .select(
                'branch_name,used_slots,remaining_slots,next_available_date,days_until_next_slot',
              )
              .inFilter('branch_name', chunk),
        );
        for (final row in rows) {
          final branch = _text(row['branch_name']);
          if (branch.isNotEmpty) output[_key(branch)] = row;
        }
      } catch (error) {
        debugPrint('Max credit preview skipped: $error');
      }
    }
    return output;
  }

  Future<List<Map<String, dynamic>>> _loadDailyExports(List<String> branches) =>
      _fetchByBranch(
        table: 'history_exports',
        branchColumn: 'branch_name',
        branches: branches,
        columns: 'branch_name,run_date,storage_path,created_at',
        orderBy: 'run_date',
      );

  Future<List<Map<String, dynamic>>> _loadNonReceivedExports(
    List<String> branches,
  ) => _fetchByBranch(
    table: 'receiving_status_exports',
    branchColumn: 'branch_name',
    branches: branches,
    columns: 'branch_name,run_date,storage_path,bucket_name,status,created_at',
    orderBy: 'run_date',
  );

  Future<List<Map<String, dynamic>>> _loadEdits(
    List<String> branches,
  ) => _fetchByBranch(
    table: 'order_edits',
    branchColumn: 'branch_name',
    branches: branches,
    columns:
        'run_date,branch_name,item_code,item_name,old_qty,new_qty,diff,created_at',
    runDateColumn: 'run_date',
    orderBy: 'created_at',
  );

  Future<List<Map<String, dynamic>>> _loadEditsRange(
    List<String> branches,
    DateTime from,
    DateTime to,
  ) async {
    if (branches.isEmpty) return const [];
    final output = <Map<String, dynamic>>[];
    final fromDate = _dateKey(from);
    final toDate = _dateKey(to);
    for (final chunk in _chunks(branches, 20)) {
      var offset = 0;
      const batchSize = 500;
      while (true) {
        final rows = List<Map<String, dynamic>>.from(
          await _client
              .from('order_edits')
              .select(
                'run_date,branch_name,item_code,item_name,old_qty,new_qty,diff,created_at',
              )
              .inFilter('branch_name', chunk)
              .gte('run_date', fromDate)
              .lte('run_date', toDate)
              .order('created_at', ascending: false)
              .range(offset, offset + batchSize - 1),
        );
        if (rows.isEmpty) break;
        output.addAll(rows);
        offset += rows.length;
      }
    }
    return output;
  }

  Future<void> _reloadEditsReport() async {
    if (_editsReportLoading || !mounted) return;
    final branches = _branches
        .map((row) => _text(row['branch_name']))
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    setState(() => _editsReportLoading = true);
    try {
      final rows = await _loadEditsRange(branches, _editsFrom, _editsTo);
      if (!mounted) return;
      setState(() => _editsReport = rows);
    } catch (error) {
      if (mounted) {
        _message('Could not load Order Edits: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _editsReportLoading = false);
    }
  }

  Future<List<_ZoneLiveActivity>> _loadRecentZoneActivity(
    List<String> branches,
  ) async {
    if (branches.isEmpty) return const [];
    final groups = await Future.wait([
      _fetchRecentActivityRows(
        table: 'max_adj',
        branches: branches,
        columns:
            'id,branch_name,item_code,item_name,current_demand_30d,max_adjustment_30d,adjustment_type,qty,reason,update_date,created_at,added_by',
        orderBy: 'created_at',
      ),
      _fetchRecentActivityRows(
        table: 'stk_mismatch',
        branches: branches,
        columns:
            'id,branch_name,item_code,item_name,system_stock,actual_stock,diff,update_date,created_at',
        orderBy: 'update_date',
      ),
    ]);
    const sources = ['max', 'mismatch'];
    final activities = <_ZoneLiveActivity>[];
    for (var index = 0; index < groups.length; index++) {
      activities.addAll(
        groups[index].map(
          (row) => _ZoneLiveActivity.fromRecord(sources[index], row),
        ),
      );
    }
    activities.sort(
      (left, right) => right.occurredAt.compareTo(left.occurredAt),
    );
    return activities.take(30).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _fetchRecentActivityRows({
    required String table,
    required List<String> branches,
    required String columns,
    required String orderBy,
    String? runDateColumn,
  }) async {
    final output = <Map<String, dynamic>>[];
    for (final chunk in _chunks(branches, 20)) {
      try {
        dynamic query = _client
            .from(table)
            .select(columns)
            .inFilter('branch_name', chunk);
        if (runDateColumn != null) {
          query = query.eq(runDateColumn, widget.runDate);
        }
        final rows = List<Map<String, dynamic>>.from(
          await query.order(orderBy, ascending: false).limit(10),
        );
        output.addAll(rows);
      } catch (error) {
        debugPrint('Live activity preview skipped for $table: $error');
      }
    }
    return output;
  }

  void _subscribeToZoneActivity(List<String> branches) {
    final previousChannel = _zoneActivityChannel;
    if (previousChannel != null) {
      _client.removeChannel(previousChannel);
    }
    _zoneActivityBranchKeys = branches.map(_key).toSet();
    _liveActivityConnected = false;
    final channel = _client
        .channel(
          'zone-manager-live-${_safe(_zoneLabel)}-${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'max_adj',
          callback: (payload) => _handleZoneActivity('max', payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stk_mismatch',
          callback: (payload) => _handleZoneActivity('mismatch', payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'additional_requests',
          callback: (payload) => _handleZoneActivity('additional', payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_submissions',
          callback: _handleZoneSubmission,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stock_check_tasks',
          callback: _handleZoneStockCheck,
        );
    _zoneActivityChannel = channel;
    channel.subscribe((status, [error]) {
      if (!mounted || _zoneActivityChannel != channel) return;
      setState(() {
        _liveActivityConnected = status == RealtimeSubscribeStatus.subscribed;
      });
    });
  }

  void _subscribeToDelegations() {
    final previous = _delegationChannel;
    if (previous != null) _client.removeChannel(previous);
    if (!_handoverAvailable) {
      _delegationChannel = null;
      return;
    }
    final uid = _client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;
    final channel = _client
        .channel('zone-handover-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'zone_management_delegations',
          callback: (payload) {
            final newRecord = Map<String, dynamic>.from(
              payload.newRecord as Map,
            );
            final oldRecord = Map<String, dynamic>.from(
              payload.oldRecord as Map,
            );
            final record = newRecord.isNotEmpty ? newRecord : oldRecord;
            if (_text(record['requester_user_id']) != uid &&
                _text(record['recipient_user_id']) != uid) {
              return;
            }
            _delegationRealtimeDebounce?.cancel();
            _delegationRealtimeDebounce = Timer(
              const Duration(milliseconds: 300),
              () {
                if (mounted) unawaited(_refreshDelegationContext());
              },
            );
          },
        );
    _delegationChannel = channel;
    channel.subscribe();
  }

  void _handleZoneActivity(String source, dynamic payload) {
    final newRecord = Map<String, dynamic>.from(payload.newRecord as Map);
    final oldRecord = Map<String, dynamic>.from(payload.oldRecord as Map);
    final record = newRecord.isNotEmpty ? newRecord : oldRecord;
    final branch = _text(record['branch_name']);
    if (branch.isEmpty || !_zoneActivityBranchKeys.contains(_key(branch))) {
      return;
    }
    final isDelete = payload.eventType == PostgresChangeEvent.delete;
    if (source == 'additional') {
      if (!mounted) return;
      final matchesDashboard = _text(record['run_date']) == widget.runDate;
      final matchesReport = _additionalRangeContains(record['run_date']);
      if (!matchesDashboard && !matchesReport) return;
      setState(() {
        if (matchesDashboard) {
          _additional = isDelete
              ? _removeRealtimeRow(_additional, record)
              : _upsertRealtimeRow(_additional, record);
        }
        if (matchesReport) {
          _additionalReport = isDelete
              ? _removeRealtimeRow(_additionalReport, record)
              : _upsertRealtimeRow(_additionalReport, record);
        }
      });
      return;
    }
    final activity = _ZoneLiveActivity.fromRecord(
      source,
      record,
      occurredAt: DateTime.now(),
      isDelete: isDelete,
    );
    if (!mounted) return;
    setState(() {
      _liveActivities = [
        activity,
        ..._liveActivities,
      ].take(30).toList(growable: false);
    });
  }

  void _handleZoneSubmission(dynamic payload) {
    final newRecord = Map<String, dynamic>.from(payload.newRecord as Map);
    final oldRecord = Map<String, dynamic>.from(payload.oldRecord as Map);
    final record = newRecord.isNotEmpty ? newRecord : oldRecord;
    final branch = _text(record['branch_name']);
    final runDate = _text(record['run_date']);
    if (branch.isEmpty ||
        runDate != widget.runDate ||
        !_zoneActivityBranchKeys.contains(_key(branch))) {
      return;
    }
    if (!mounted) return;
    setState(() {
      final updated = Map<String, Map<String, dynamic>>.from(_submissions);
      if (payload.eventType == PostgresChangeEvent.delete) {
        updated.remove(_key(branch));
      } else {
        updated[_key(branch)] = record;
      }
      _submissions = updated;
    });
  }

  void _handleZoneStockCheck(dynamic payload) {
    final newRecord = Map<String, dynamic>.from(payload.newRecord as Map);
    final oldRecord = Map<String, dynamic>.from(payload.oldRecord as Map);
    final record = newRecord.isNotEmpty ? newRecord : oldRecord;
    final branch = _text(record['branch_name']);
    if (branch.isEmpty ||
        !_zoneActivityBranchKeys.contains(_key(branch)) ||
        _text(record['source']).toLowerCase() != 'inventory' ||
        !mounted) {
      return;
    }

    _stockCheckRealtimeDebounce?.cancel();
    _stockCheckRealtimeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(_refreshDashboardStockChecks());
      if (_page == 6) unawaited(_loadStockChecks());
    });
  }

  Future<List<StockCheckTask>> _loadDashboardStockChecks(
    List<String> branches,
  ) async {
    if (branches.isEmpty) return const [];
    final output = <StockCheckTask>[];
    for (final chunk in _chunks(branches, 20)) {
      var offset = 0;
      const batchSize = 500;
      while (true) {
        final data = List<Map<String, dynamic>>.from(
          await _client
              .from('stock_check_tasks')
              .select()
              .eq('source', 'inventory')
              .neq('status', 'submitted')
              .inFilter('branch_name', chunk)
              .order('expires_at')
              .range(offset, offset + batchSize - 1),
        );
        if (data.isEmpty) break;
        output.addAll(data.map(StockCheckTask.fromMap));
        offset += data.length;
      }
    }
    return output;
  }

  Future<void> _refreshDashboardStockChecks() async {
    if (_dashboardStockCheckSyncing || !mounted) return;
    final branches = _branches
        .map((row) => _text(row['branch_name']))
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (branches.isEmpty) return;
    _dashboardStockCheckSyncing = true;
    try {
      final latest = await _loadDashboardStockChecks(branches);
      if (!mounted) return;
      final latestSignature = _dashboardStockCheckSignature(latest);
      final currentSignature = _dashboardStockCheckSignature(
        _dashboardStockChecks,
      );
      final clockMinute =
          DateTime.now().millisecondsSinceEpoch ~/
          Duration.millisecondsPerMinute;
      if (latestSignature != currentSignature ||
          clockMinute != _dashboardStockCheckClockMinute) {
        setState(() {
          _dashboardStockChecks = latest;
          _dashboardStockCheckClockMinute = clockMinute;
        });
      }
    } catch (error) {
      debugPrint('Dashboard Stock Check sync skipped: $error');
    } finally {
      _dashboardStockCheckSyncing = false;
    }
  }

  String _dashboardStockCheckSignature(List<StockCheckTask> tasks) {
    final values =
        tasks
            .map(
              (task) =>
                  '${task.id}|${task.batchId}|${task.branchName}|${task.status}|${task.expiresAt?.millisecondsSinceEpoch ?? 0}',
            )
            .toList(growable: false)
          ..sort();
    return values.join('~');
  }

  List<Map<String, dynamic>> _upsertRealtimeRow(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> record,
  ) {
    final id = _text(record['id']);
    final updated = rows
        .where((row) => id.isEmpty || _text(row['id']) != id)
        .toList();
    updated.insert(0, record);
    return updated;
  }

  List<Map<String, dynamic>> _removeRealtimeRow(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> record,
  ) {
    final id = _text(record['id']);
    if (id.isEmpty) return rows;
    return rows.where((row) => _text(row['id']) != id).toList(growable: false);
  }

  Future<void> _loadStockChecks() async {
    if (_stockCheckLoading) return;
    final branches = _branches
        .map((row) => _text(row['branch_name']))
        .where((name) => name.isNotEmpty)
        .toList();
    if (branches.isEmpty) return;
    setState(() {
      _stockCheckLoading = true;
      _stockCheckError = null;
    });
    try {
      final output = <StockCheckTask>[];
      for (final chunk in _chunks(branches, 20)) {
        var offset = 0;
        const batchSize = 500;
        while (true) {
          final data = List<Map<String, dynamic>>.from(
            await _client
                .from('stock_check_tasks')
                .select()
                .eq('source', 'inventory')
                .inFilter('branch_name', chunk)
                .order('sent_at', ascending: false)
                .range(offset, offset + batchSize - 1),
          );
          if (data.isEmpty) break;
          output.addAll(data.map(StockCheckTask.fromMap));
          offset += data.length;
        }
      }
      output.sort((left, right) {
        final byBranch = _key(
          left.branchName,
        ).compareTo(_key(right.branchName));
        if (byBranch != 0) return byBranch;
        return (right.sentAt ?? DateTime(1970)).compareTo(
          left.sentAt ?? DateTime(1970),
        );
      });
      if (!mounted) return;
      setState(() => _stockChecks = output);
    } catch (error) {
      if (!mounted) return;
      setState(() => _stockCheckError = error.toString());
    } finally {
      if (mounted) setState(() => _stockCheckLoading = false);
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadSubmissions(
    List<String> branches,
  ) async {
    final rows = await _fetchByBranch(
      table: 'order_submissions',
      branchColumn: 'branch_name',
      branches: branches,
      columns: 'branch_name,submitted_at,status',
      runDateColumn: 'run_date',
    );
    return {for (final row in rows) _key(row['branch_name']): row};
  }

  Future<List<Map<String, dynamic>>> _fetchByBranch({
    required String table,
    required String branchColumn,
    required List<String> branches,
    required String columns,
    String? runDateColumn,
    String? orderBy,
    String? tieBreaker,
  }) async {
    if (branches.isEmpty) return const [];
    final output = <Map<String, dynamic>>[];
    for (final chunk in _chunks(branches, 20)) {
      var offset = 0;
      const batch = 500;
      while (true) {
        dynamic query = _client
            .from(table)
            .select(columns)
            .inFilter(branchColumn, chunk);
        if (runDateColumn != null) {
          query = query.eq(runDateColumn, widget.runDate);
        }
        if (orderBy != null) {
          query = query.order(orderBy, ascending: false);
        }
        if (tieBreaker != null && tieBreaker != orderBy) {
          query = query.order(tieBreaker, ascending: false);
        }
        final data = List<Map<String, dynamic>>.from(
          await query.range(offset, offset + batch - 1),
        );
        if (data.isEmpty) break;
        output.addAll(data);
        offset += data.length;
      }
    }
    return output;
  }

  Future<void> _changePage(int page) async {
    final leavingDailyOrder = _page == 3 && page != 3;
    if (_page != page) {
      _search.clear();
      _query = '';
    }
    if (leavingDailyOrder) {
      _selectedBranch = 'ALL';
    }
    if (page == 3 && _selectedBranch == 'ALL' && _branches.isNotEmpty) {
      _selectedBranch = _text(_branches.first['branch_name']);
    }
    setState(() => _page = page);
    if (page == 3) {
      final key = '$_selectedBranch|${widget.runDate}';
      if (_dailyRequestKey != key || _dailyRows.isEmpty) {
        await _loadDailyBranch();
      }
      return;
    }
    if (page == 6) {
      if (_stockChecks.isEmpty) await _loadStockChecks();
      return;
    }
    await _loadZoneReport(page);
  }

  Future<void> _loadZoneReport(int page, {bool force = false}) async {
    if (page != 1 && page != 2) return;
    if (!force && page == 1 && _mismatch.isNotEmpty) return;
    if (!force && page == 2 && _maxAdj.isNotEmpty) return;
    setState(() => _reportLoading = true);
    try {
      final branches = _branches
          .map((row) => _text(row['branch_name']))
          .where((name) => name.isNotEmpty)
          .toList();
      final rows = page == 1
          ? await _loadMismatch(branches)
          : await _loadMaxAdj(branches);
      rows.sort(_compareBranchItem);
      if (!mounted) return;
      setState(() {
        if (page == 1) {
          _mismatch = rows;
        } else {
          _maxAdj = rows;
        }
      });
    } catch (error) {
      _message('Could not load ${_pages[page].label}: $error', error: true);
    } finally {
      if (mounted) setState(() => _reportLoading = false);
    }
  }

  List<List<String>> _chunks(List<String> values, int size) => [
    for (var i = 0; i < values.length; i += size)
      values.sublist(i, (i + size).clamp(0, values.length)),
  ];

  bool _visible(Map<String, dynamic> row, String branchColumn) {
    final branch = _text(row[branchColumn]);
    if (_selectedBranch != 'ALL' && branch != _selectedBranch) return false;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return row.values.any(
      (value) => _text(value).toLowerCase().contains(query),
    );
  }

  List<Map<String, dynamic>> _filtered(
    List<Map<String, dynamic>> rows,
    String branchColumn,
  ) => rows.where((row) => _visible(row, branchColumn)).toList();

  int _compareBranchItem(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final byBranch = _key(
      left['branch_name'],
    ).compareTo(_key(right['branch_name']));
    if (byBranch != 0) return byBranch;
    return _key(left['item_code']).compareTo(_key(right['item_code']));
  }

  void _onBranchChanged(String value) {
    setState(() {
      _selectedBranch = value;
      if (_page == 6) _selectedStockCheckBatchId = null;
    });
    if (_page == 3) _loadDailyBranch();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
  }

  Future<void> _downloadExport(
    Map<String, dynamic> row, {
    required bool nonReceived,
  }) async {
    final path = _text(row['storage_path']);
    if (path.isEmpty) return;
    setState(() => _busy = true);
    try {
      final bucket = nonReceived
          ? (_text(row['bucket_name']).isEmpty
                ? 'non-recived-exports'
                : _text(row['bucket_name']))
          : 'history-exports';
      final url = await _client.storage.from(bucket).createSignedUrl(path, 60);
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('The browser blocked the download.');
      }
    } catch (error) {
      _message('Download failed: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadExportBatch(
    List<Map<String, dynamic>> rows, {
    required bool nonReceived,
  }) async {
    if (rows.isEmpty) {
      _message('No files match this selection.', error: true);
      return;
    }
    if (rows.length == 1) {
      await _downloadExport(rows.single, nonReceived: nonReceived);
      return;
    }
    setState(() => _busy = true);
    try {
      final archive = Archive();
      for (final row in rows) {
        final path = _text(row['storage_path']);
        if (path.isEmpty) continue;
        final bucket = nonReceived
            ? (_text(row['bucket_name']).isEmpty
                  ? 'non-recived-exports'
                  : _text(row['bucket_name']))
            : 'history-exports';
        final bytes = await _client.storage.from(bucket).download(path);
        final branch = _safe(_text(row['branch_name']));
        final date = _safe(_text(row['run_date']));
        final original = path.split('/').last;
        final fileName = original.toLowerCase().endsWith('.xlsx')
            ? '${branch}_$original'
            : '${branch}_${date}_$original.xlsx';
        archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
      }
      if (archive.isEmpty) {
        throw Exception('No downloadable files were found.');
      }
      final zip = ZipEncoder().encode(archive);
      final blob = html.Blob([zip]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final title = nonReceived ? 'Non_Received' : 'Daily_Order_History';
      html.AnchorElement(href: url)
        ..download = '${title}_${_safe(_zoneLabel)}.zip'
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (error) {
      _message('Zone download failed: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportExcel(
    String title,
    List<Map<String, dynamic>> rows,
    List<_ColumnDef> columns,
  ) async {
    if (rows.isEmpty) {
      _message('There is no data to export.', error: true);
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(Duration.zero);
    try {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Zone Report';
      final titleRange = sheet.getRangeByIndex(1, 1, 1, columns.length);
      titleRange.merge();
      titleRange.setText('$title • $_zoneLabel');
      titleRange.cellStyle
        ..backColor = '#122D40'
        ..fontColor = '#FFFFFF'
        ..bold = true
        ..fontSize = 15
        ..hAlign = xlsio.HAlignType.center;
      for (var col = 0; col < columns.length; col++) {
        final cell = sheet.getRangeByIndex(3, col + 1);
        cell.setText(columns[col].label);
        cell.cellStyle
          ..backColor = '#DCEBFF'
          ..bold = true
          ..fontColor = '#0B1B4C';
      }
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        for (var col = 0; col < columns.length; col++) {
          final value = rows[rowIndex][columns[col].key];
          final cell = sheet.getRangeByIndex(rowIndex + 4, col + 1);
          if (value is num) {
            cell.setNumber(value.toDouble());
          } else {
            cell.setText(_text(value));
          }
        }
      }
      for (var col = 1; col <= columns.length; col++) {
        sheet.autoFitColumn(col);
      }
      final bytes = workbook.saveAsStream();
      workbook.dispose();
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final date = DateFormat('yyyyMMdd').format(DateTime.now());
      html.AnchorElement(href: url)
        ..download = '${_safe(title)}_${_safe(_zoneLabel)}_$date.xlsx'
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (error) {
      _message('Excel export failed: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  void _openBranch(String branch) {
    final additionalCount = _additional
        .where((row) => _key(row['branch_name']) == _key(branch))
        .length;
    final editCount = _edits
        .where((row) => _key(row['branch_name']) == _key(branch))
        .length;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .34),
      builder: (_) => _BranchQuickView(
        branch: branch,
        runDate: widget.runDate,
        submitted: _submissions.containsKey(_key(branch)),
        additionalCount: additionalCount,
        editCount: editCount,
        onOpenDaily: () {
          Navigator.pop(context);
          setState(() {
            _selectedBranch = branch;
          });
          _changePage(3);
        },
        onOpenAdditional: () {
          Navigator.pop(context);
          setState(() {
            _selectedBranch = branch;
            _page = 4;
          });
        },
        onOpenHistory: () {
          Navigator.pop(context);
          setState(() {
            _selectedBranch = branch;
            _page = 8;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xffF4F7FB),
        body: _ZoneOperationOverlay(
          label: 'Loading your zone workspace…',
          dimBackground: false,
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xffF4F7FB),
        body: _ErrorView(message: _error!, onRetry: _load),
      );
    }
    // Page-level fetches already render their own loading state. Keep this
    // overlay only for actions that have no dedicated in-page indicator.
    final showOperationLoading = _busy || _handoverBusy;
    final operationLabel = _handoverBusy
        ? 'Updating zone handover…'
        : 'Preparing your request…';
    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),
      body: Stack(
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: _drawerCollapsed ? 0 : 270,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _drawerCollapsed ? 0 : 1,
                    child: _ZoneDrawer(
                      currentPage: _page,
                      zoneName: _zoneLabel,
                      onChanged: _changePage,
                    ),
                  ),
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
          Positioned(
            top: 22,
            left: _drawerCollapsed ? 10 : 252,
            child: _DrawerToggle(
              collapsed: _drawerCollapsed,
              onTap: () => setState(() => _drawerCollapsed = !_drawerCollapsed),
            ),
          ),
          if (showOperationLoading)
            Positioned.fill(
              child: _ZoneOperationOverlay(label: operationLabel),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _ZoneHeader(
          title: _page == 0 ? 'Zone Manager Dashboard' : _pages[_page].label,
          zoneName: _zoneLabel,
          runDate: widget.runDate,
          branches: _branches.map((row) => _text(row['branch_name'])).toList(),
          selectedBranch: _selectedBranch,
          allowAllBranches: _page != 3,
          onBranchChanged: _onBranchChanged,
          onRefresh: _load,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          reverseDuration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            axisAlignment: -1,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _selectedBranch != 'ALL' && _page != 3
              ? Padding(
                  key: ValueKey('active-filter-$_selectedBranch'),
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
                  child: _ZoneActiveFilterBanner(
                    branchName: _selectedBranch,
                    onClear: () => _onBranchChanged('ALL'),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-active-filter')),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 340),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(.025, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey('page-$_page-branch-$_selectedBranch'),
                child: SelectionArea(child: _buildCurrentZonePage()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentZonePage() => switch (_page) {
    0 => buildZoneDashboardPage(),
    1 => buildZoneMismatchPage(),
    2 => buildZoneMaxAdjustmentPage(),
    3 => buildZoneDailyOrderPage(),
    4 => buildZoneAdditionalOrdersPage(),
    5 => buildZoneOrderEditsPage(),
    6 => buildZoneStockCheckPage(),
    7 => buildZoneNonReceivedPage(),
    8 => buildZoneDailyOrderHistoryPage(),
    _ => buildZoneHandoverPage(),
  };
}

class _ZoneDrawer extends StatelessWidget {
  final int currentPage;
  final String zoneName;
  final ValueChanged<int> onChanged;

  const _ZoneDrawer({
    required this.currentPage,
    required this.zoneName,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      color: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
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
                Image.asset(
                  'assets/images/logo1.png',
                  width: 120,
                  height: 70,
                  fit: BoxFit.cover,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Zone Management',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.blueSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    zoneName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.secondaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _ZoneManagerPageState._pages.length,
              itemBuilder: (_, index) {
                final page = _ZoneManagerPageState._pages[index];
                final selected = currentPage == index;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    onTap: () => onChanged(index),
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 15,
                      ),
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
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: AppColors.primaryColor.withValues(
                                    alpha: .25,
                                  ),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            page.icon,
                            size: 23,
                            color: selected
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              page.label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white
                                    : Colors.grey.shade800,
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
          ),
        ],
      ),
    );
  }
}

class _ZoneHeader extends StatelessWidget {
  final String title, zoneName, runDate, selectedBranch;
  final List<String> branches;
  final ValueChanged<String> onBranchChanged;
  final VoidCallback onRefresh;
  final bool allowAllBranches;

  const _ZoneHeader({
    required this.title,
    required this.zoneName,
    required this.runDate,
    required this.branches,
    required this.selectedBranch,
    required this.allowAllBranches,
    required this.onBranchChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final sortedBranches = [
      ...branches,
    ]..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
    return Padding(
      padding: const EdgeInsets.fromLTRB(38, 20, 24, 10),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo1.png',
            width: 88,
            height: 48,
            fit: BoxFit.cover,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$zoneName • ${_displayDate(runDate)}',
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 205,
            child: DropdownButtonFormField<String>(
              key: ValueKey(selectedBranch),
              initialValue: selectedBranch,
              isExpanded: true,
              decoration: _inputDecoration('Branch', Icons.store_outlined),
              items: [if (allowAllBranches) 'ALL', ...sortedBranches]
                  .map(
                    (branch) => DropdownMenuItem(
                      value: branch,
                      child: Text(
                        branch == 'ALL' ? 'All Branches' : branch,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onBranchChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneActiveFilterBanner extends StatelessWidget {
  final String branchName;
  final VoidCallback onClear;

  const _ZoneActiveFilterBanner({
    required this.branchName,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xff7C3AED);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.elasticOut,
      builder: (context, value, child) => Transform.scale(
        scale: .97 + (.03 * value),
        alignment: Alignment.centerLeft,
        child: child,
      ),
      child: Container(
        height: 54,
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xffF5F3FF), Color(0xffEFF6FF)],
          ),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: accent.withValues(alpha: .28)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: .10),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: .26),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.filter_alt_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
            const SizedBox(width: 11),
            const Text(
              'FILTER ACTIVE',
              style: TextStyle(
                color: accent,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .9,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: .24)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_rounded, color: accent, size: 16),
                  const SizedBox(width: 7),
                  Text(
                    branchName,
                    style: const TextStyle(
                      color: AppColors.secondaryColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Page data is filtered to this branch • Live Activity continues monitoring the full zone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.subText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onClear,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: .34)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const Text(
                'Clear Filter',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportPage extends StatelessWidget {
  final String title, subtitle;
  final Color accent;
  final List<Map<String, dynamic>> rows;
  final List<_ColumnDef> columns;
  final VoidCallback onExport;
  final List<_ReportKpi> kpis;
  final List<Widget> extraActions;
  final String exportLabel;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String searchHint;
  const _ReportPage({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.rows,
    required this.columns,
    required this.onExport,
    required this.searchController,
    required this.onSearchChanged,
    this.kpis = const [],
    this.extraActions = const [],
    this.exportLabel = 'Export Excel',
    this.searchHint = 'Search this table…',
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ModernPageHero(
          icon: title.contains('Mismatch')
              ? Icons.warning_amber_rounded
              : title.contains('Max')
              ? Icons.trending_up_rounded
              : title.contains('Edit')
              ? Icons.edit_note_rounded
              : title.contains('Stock Check')
              ? Icons.fact_check_outlined
              : Icons.view_list_rounded,
          eyebrow: 'ZONE CONTROL CENTER',
          title: title,
          subtitle: subtitle,
          accent: accent,
          metrics: const [],
          actions: [
            ...extraActions,
            FilledButton.icon(
              onPressed: rows.isEmpty ? null : onExport,
              style: FilledButton.styleFrom(backgroundColor: accent),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(exportLabel),
            ),
          ],
        ),
        if (kpis.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ReportKpiStrip(kpis: kpis),
        ],
        const SizedBox(height: 10),
        _ZoneTableToolbar(
          controller: searchController,
          onChanged: onSearchChanged,
          accent: accent,
          resultCount: rows.length,
          hintText: searchHint,
          showResizeHint: true,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _DataTableCard(rows: rows, columns: columns, accent: accent),
        ),
      ],
    );
  }
}

class _ZoneTableToolbar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Color accent;
  final int resultCount;
  final String hintText;
  final bool showResizeHint;

  const _ZoneTableToolbar({
    required this.controller,
    required this.onChanged,
    required this.accent,
    required this.resultCount,
    required this.hintText,
    this.showResizeHint = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0F2942).withValues(alpha: .045),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.manage_search_rounded, color: accent, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: AppColors.secondaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(color: AppColors.subText),
                border: InputBorder.none,
                isDense: true,
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: .18)),
            ),
            child: Text(
              '$resultCount results',
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (showResizeHint) ...[
            const SizedBox(width: 12),
            const Icon(
              Icons.width_normal_rounded,
              size: 17,
              color: AppColors.subText,
            ),
            const SizedBox(width: 6),
            const Text(
              'Drag column edges to resize',
              style: TextStyle(
                color: AppColors.subText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportKpi {
  final IconData icon;
  final String title, value, subtitle;
  final Color color;
  const _ReportKpi(
    this.icon,
    this.title,
    this.value,
    this.subtitle,
    this.color,
  );
}

class _ReportKpiStrip extends StatelessWidget {
  final List<_ReportKpi> kpis;
  const _ReportKpiStrip({required this.kpis});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < kpis.length; index++) ...[
        Expanded(child: _ReportKpiCard(kpi: kpis[index])),
        if (index < kpis.length - 1) const SizedBox(width: 10),
      ],
    ],
  );
}

class _ReportKpiCard extends StatefulWidget {
  final _ReportKpi kpi;
  const _ReportKpiCard({required this.kpi});

  @override
  State<_ReportKpiCard> createState() => _ReportKpiCardState();
}

class _ReportKpiCardState extends State<_ReportKpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final kpi = widget.kpi;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 100,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered
                ? kpi.color.withValues(alpha: .50)
                : AppColors.border.withValues(alpha: .9),
            width: _hovered ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xff0F2942,
              ).withValues(alpha: _hovered ? .13 : .055),
              blurRadius: _hovered ? 22 : 14,
              offset: Offset(0, _hovered ? 8 : 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: kpi.color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(kpi.icon, color: kpi.color, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kpi.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.subText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kpi.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.secondaryColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    kpi.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.subText,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyPagination extends StatelessWidget {
  final String branch, runDate;
  final int total, pageIndex, pageSize;
  final bool loading;
  final VoidCallback? onPrevious, onNext;
  final VoidCallback onHistory;

  const _DailyPagination({
    required this.branch,
    required this.runDate,
    required this.total,
    required this.pageIndex,
    required this.pageSize,
    required this.loading,
    required this.onPrevious,
    required this.onNext,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : (pageIndex * pageSize) + 1;
    final to = ((pageIndex + 1) * pageSize).clamp(0, total);
    final pages = total == 0 ? 1 : (total / pageSize).ceil();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffEAF6FC), Color(0xffF7FBFE)],
        ),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  size: 17,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(width: 7),
                Text(
                  branch == 'ALL' ? 'All Zone Branches' : branch,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$from-$to of $total  •  Page ${pageIndex + 1} of $pages  •  ${_displayDate(runDate)}',
            style: const TextStyle(
              color: AppColors.subText,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (loading) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: onHistory,
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('Daily Order History'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Previous'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class _DailyOrderError extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  const _DailyOrderError({
    this.title = 'Daily Order could not be loaded',
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 560,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: .22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Colors.redAccent,
            size: 46,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.subText),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );
}

class _DataTableCard extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final List<_ColumnDef> columns;
  final Color accent;
  const _DataTableCard({
    required this.rows,
    required this.columns,
    required this.accent,
  });

  @override
  State<_DataTableCard> createState() => _DataTableCardState();
}

class _DataTableCardState extends State<_DataTableCard> {
  final Map<String, double> _resizedWidths = {};

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) return _EmptyState(color: widget.accent);
    final source = _ZoneGridSource(
      rows: widget.rows,
      columns: widget.columns,
      accent: widget.accent,
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0F2942).withValues(alpha: .055),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SfDataGridTheme(
          data: SfDataGridThemeData(
            headerColor: widget.accent.withValues(alpha: .09),
            gridLineColor: AppColors.border.withValues(alpha: .72),
            selectionColor: widget.accent.withValues(alpha: .10),
            filterIconColor: widget.accent,
            sortIconColor: widget.accent,
            filterPopupBackgroundColor: Colors.white,
            filterPopupTextStyle: const TextStyle(
              color: Color(0xff1E293B),
              fontWeight: FontWeight.w500,
            ),
            filterPopupDisabledTextStyle: const TextStyle(
              color: Color(0xff94A3B8),
            ),
            filterPopupIconColor: AppColors.primaryColor,
            filterPopupDisabledIconColor: const Color(0xffCBD5E1),
            filterPopupInputBorderColor: AppColors.primaryColor,
            filterPopupCheckColor: Colors.white,
            filterPopupCheckboxFillColor:
                WidgetStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return const Color(0xffE2E8F0);
                  }
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primaryColor;
                  }
                  return Colors.white;
                }),
            okFilteringLabelButtonColor: AppColors.primaryColor,
            okFilteringLabelColor: Colors.white,
            cancelFilteringLabelButtonColor: Colors.white,
            cancelFilteringLabelColor: AppColors.primaryColor,
            searchAreaFocusedBorderColor: AppColors.primaryColor,
            searchAreaCursorColor: AppColors.primaryColor,
            filterPopupTopDividerColor: AppColors.border,
            filterPopupBottomDividerColor: AppColors.border,
          ),
          child: SfDataGrid(
            source: source,
            allowSorting: true,
            allowMultiColumnSorting: true,
            allowFiltering: true,
            allowColumnsResizing: true,
            onColumnResizeUpdate: (details) {
              setState(() {
                _resizedWidths[details.column.columnName] = details.width;
              });
              return true;
            },
            columnWidthMode: ColumnWidthMode.none,
            gridLinesVisibility: GridLinesVisibility.both,
            headerGridLinesVisibility: GridLinesVisibility.vertical,
            frozenColumnsCount: 1,
            rowHeight: 62,
            headerRowHeight: 64,
            columns: widget.columns
                .map(
                  (column) => GridColumn(
                    columnName: column.key,
                    width:
                        _resizedWidths[column.key] ??
                        (_columnWidth(column.key) + 34),
                    minimumWidth: 110,
                    label: Container(
                      alignment: column.key == 'item_name'
                          ? Alignment.centerLeft
                          : Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        column.label.toUpperCase(),
                        maxLines: 2,
                        textAlign: column.key == 'item_name'
                            ? TextAlign.left
                            : TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.secondaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .35,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _ZoneGridSource extends DataGridSource {
  final List<Map<String, dynamic>> sourceRows;
  final List<_ColumnDef> columns;
  final Color accent;
  late final List<DataGridRow> _gridRows;
  final Map<DataGridRow, int> _rowIndexes = {};

  _ZoneGridSource({
    required List<Map<String, dynamic>> rows,
    required this.columns,
    required this.accent,
  }) : sourceRows = rows {
    _gridRows = sourceRows
        .map(
          (row) => DataGridRow(
            cells: columns
                .map(
                  (column) => DataGridCell<dynamic>(
                    columnName: column.key,
                    value: row[column.key],
                  ),
                )
                .toList(),
          ),
        )
        .toList(growable: false);
    for (var index = 0; index < _gridRows.length; index++) {
      _rowIndexes[_gridRows[index]] = index;
    }
  }

  @override
  List<DataGridRow> get rows => _gridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final index = _rowIndexes[row] ?? 0;
    return DataGridRowAdapter(
      color: index.isEven ? Colors.white : const Color(0xffF8FBFD),
      cells: row.getCells().map((cell) {
        final key = cell.columnName;
        final value = cell.value;
        Widget child;
        if (key == 'status') {
          child = Align(
            alignment: Alignment.center,
            child: _StatusChip(_text(value)),
          );
        } else if (key == 'diff' || key == 'remaining_qty') {
          child = Align(
            alignment: Alignment.center,
            child: _DifferenceCell(value),
          );
        } else {
          final isIdentity = key == 'branch' || key == 'branch_name';
          child = Text(
            _displayValue(key, value),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: key == 'item_name' || isIdentity
                ? TextAlign.left
                : TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isIdentity ? FontWeight.w800 : FontWeight.w500,
              color: isIdentity
                  ? AppColors.secondaryColor
                  : const Color(0xff334155),
            ),
          );
        }
        return Container(
          alignment:
              key == 'item_name' || key == 'branch' || key == 'branch_name'
              ? Alignment.centerLeft
              : Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: key == 'branch_name' || key == 'branch'
              ? BoxDecoration(
                  border: Border(left: BorderSide(color: accent, width: 3)),
                )
              : null,
          child: child,
        );
      }).toList(),
    );
  }
}

class _LegacyDataTableCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final List<_ColumnDef> columns;
  final Color accent;
  const _LegacyDataTableCard({
    required this.rows,
    required this.columns,
    required this.accent,
  });
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _EmptyState(color: accent);
    var branchGroup = -1;
    var lastBranch = '';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  accent.withValues(alpha: .12),
                ),
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondaryColor,
                ),
                columns: columns
                    .map(
                      (column) => DataColumn(
                        label: SizedBox(
                          width: _columnWidth(column.key),
                          child: Text(column.label),
                        ),
                      ),
                    )
                    .toList(),
                rows: rows.map((row) {
                  final branch = _key(row['branch_name'] ?? row['branch']);
                  if (branch.isNotEmpty && branch != lastBranch) {
                    branchGroup++;
                    lastBranch = branch;
                  }
                  return DataRow(
                    color: WidgetStatePropertyAll(
                      branchGroup.isEven
                          ? accent.withValues(alpha: .035)
                          : Colors.white,
                    ),
                    cells: columns.map((column) {
                      final value = row[column.key];
                      if (column.key == 'status') {
                        return DataCell(_StatusChip(_text(value)));
                      }
                      if (column.key == 'diff' ||
                          column.key == 'remaining_qty') {
                        return DataCell(_DifferenceCell(value));
                      }
                      return DataCell(
                        SizedBox(
                          width: _columnWidth(column.key),
                          child: Text(
                            _displayValue(column.key, value),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                column.key == 'branch' ||
                                    column.key == 'branch_name'
                                ? const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.secondaryColor,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final ValueChanged<Map<String, dynamic>> onDownload;
  const _ExportList({required this.rows, required this.onDownload});
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _EmptyState(color: AppColors.primaryColor);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final row = rows[index];
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.blueSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.table_view_rounded,
                color: AppColors.primaryColor,
              ),
            ),
            title: Text(
              _text(row['branch_name']),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('Run date: ${_text(row['run_date'])}'),
            trailing: FilledButton.tonalIcon(
              onPressed: () => onDownload(row),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download Excel'),
            ),
          );
        },
      ),
    );
  }
}

class _BranchDetailsDialog extends StatelessWidget {
  final String branch, runDate;
  final List<Map<String, dynamic>> daily,
      additional,
      mismatch,
      maxAdj,
      nonReceived;
  const _BranchDetailsDialog({
    required this.branch,
    required this.runDate,
    required this.daily,
    required this.additional,
    required this.mismatch,
    required this.maxAdj,
    required this.nonReceived,
  });
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: SizedBox(
      width: 1320,
      height: 780,
      child: DefaultTabController(
        length: 5,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 14, 14),
              decoration: const BoxDecoration(
                color: Color(0xffEAF6FC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.store_rounded,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          branch,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondaryColor,
                          ),
                        ),
                        Text(
                          'Complete branch details • ${_displayDate(runDate)}',
                          style: const TextStyle(color: AppColors.subText),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _DetailMetric('Daily Lines', daily.length, Colors.deepPurple),
                  _DetailMetric('Additional', additional.length, Colors.orange),
                  _DetailMetric('Mismatch', mismatch.length, Colors.red),
                  _DetailMetric('Max Adj', maxAdj.length, Colors.blue),
                  _DetailMetric(
                    'Non Received',
                    nonReceived.length,
                    Colors.redAccent,
                  ),
                ],
              ),
            ),
            const TabBar(
              labelColor: AppColors.primaryColor,
              unselectedLabelColor: AppColors.subText,
              indicatorColor: AppColors.primaryColor,
              tabs: [
                Tab(text: 'Daily Order'),
                Tab(text: 'Additional'),
                Tab(text: 'Mismatch'),
                Tab(text: 'Max Adjustment'),
                Tab(text: 'Non Received'),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TabBarView(
                  children: [
                    _DataTableCard(
                      rows: daily,
                      columns: const [
                        _ColumnDef('item_code', 'Item Code'),
                        _ColumnDef('item_name', 'Item Name'),
                        _ColumnDef('branch_stock', 'Branch Stock'),
                        _ColumnDef('store_stock', 'Store Stock'),
                        _ColumnDef(
                          'pending_stock_received',
                          'Pending Received',
                        ),
                        _ColumnDef(
                          'final_reorder_qty_store_stock_gt_0',
                          'Final Order',
                        ),
                      ],
                      accent: AppColors.primaryColor,
                    ),
                    _DataTableCard(
                      rows: additional,
                      columns: const [
                        _ColumnDef('item_code', 'Item Code'),
                        _ColumnDef('item_name', 'Item Name'),
                        _ColumnDef('request_qty', 'Requested'),
                        _ColumnDef('inventory_qty', 'Inventory'),
                        _ColumnDef('fulfilled_qty', 'Fulfilled'),
                        _ColumnDef('status', 'Status'),
                      ],
                      accent: Colors.orange,
                    ),
                    _DataTableCard(
                      rows: mismatch,
                      columns: const [
                        _ColumnDef('item_code', 'Item Code'),
                        _ColumnDef('item_name', 'Item Name'),
                        _ColumnDef('system_stock', 'System Stock'),
                        _ColumnDef('actual_stock', 'Actual Stock'),
                        _ColumnDef('diff', 'Diff'),
                        _ColumnDef('update_date', 'Updated'),
                      ],
                      accent: Colors.red,
                    ),
                    _DataTableCard(
                      rows: maxAdj,
                      columns: const [
                        _ColumnDef('item_code', 'Item Code'),
                        _ColumnDef('item_name', 'Item Name'),
                        _ColumnDef('current_demand_30d', 'Demand'),
                        _ColumnDef('max_adjustment_30d', 'Max Adj'),
                        _ColumnDef('qty', 'Qty'),
                        _ColumnDef('reason', 'Reason'),
                      ],
                      accent: Colors.orange,
                    ),
                    _DataTableCard(
                      rows: nonReceived,
                      columns: const [
                        _ColumnDef('item_code', 'Item Code'),
                        _ColumnDef('item_name', 'Item Name'),
                        _ColumnDef(
                          'final_reorder_qty_store_stock_gt_0',
                          'Daily Order',
                        ),
                        _ColumnDef('transferred_qty', 'Transferred'),
                        _ColumnDef('remaining_qty', 'Non Received'),
                        _ColumnDef('status', 'Status'),
                        _ColumnDef('note', 'Details'),
                      ],
                      accent: Colors.redAccent,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DownloadCenter extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final List<Map<String, dynamic>> rows;
  final List<String> zoneBranches;
  final ValueChanged<Map<String, dynamic>> onDownloadOne;
  final ValueChanged<List<Map<String, dynamic>>> onDownloadSelection;

  const _DownloadCenter({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.rows,
    required this.zoneBranches,
    required this.onDownloadOne,
    required this.onDownloadSelection,
  });

  @override
  State<_DownloadCenter> createState() => _DownloadCenterState();
}

class _DownloadCenterState extends State<_DownloadCenter> {
  String _branch = 'ALL';
  String? _date;

  static const Color _pageText = Color(0xFF172033);
  static const Color _secondaryText = Color(0xFF64748B);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _softSurface = Color(0xFFF8FAFC);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _borderStrong = Color(0xFFCBD5E1);
  static const Color _success = Color(0xFF16A34A);
  static const Color _successSoft = Color(0xFFECFDF3);
  static const Color _successBorder = Color(0xFFBBF7D0);
  static const Color _purple = Color(0xFF7C3AED);
  static const Color _purpleSoft = Color(0xFFF5F3FF);

  List<String> get _dates {
    final values =
        widget.rows
            .map((row) => _text(row['run_date']))
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) {
            final aDate = DateTime.tryParse(a);
            final bDate = DateTime.tryParse(b);
            if (aDate != null && bDate != null) {
              return bDate.compareTo(aDate);
            }
            return b.toLowerCase().compareTo(a.toLowerCase());
          });

    return values;
  }

  String? get _selectedDate {
    final dates = _dates;

    if (dates.isEmpty) {
      return null;
    }

    if (_date != null && dates.contains(_date)) {
      return _date;
    }

    return dates.first;
  }

  List<Map<String, dynamic>> get _selection {
    final date = _selectedDate;

    if (date == null) {
      return const [];
    }

    final rows = widget.rows.where((row) {
      final dateMatches = _text(row['run_date']) == date;
      final branchMatches =
          _branch == 'ALL' || _text(row['branch_name']) == _branch;
      final hasFile = _text(row['storage_path']).isNotEmpty;

      return dateMatches && branchMatches && hasFile;
    }).toList();

    rows.sort(
      (left, right) =>
          _text(left['branch_name']).compareTo(_text(right['branch_name'])),
    );

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final dates = _dates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportHeading(title: widget.title, subtitle: widget.subtitle),
        const SizedBox(height: 16),
        _buildFilterPanel(selection: selection, dates: dates),
        const SizedBox(height: 18),
        Expanded(
          child: selection.isEmpty
              ? _EmptyState(color: widget.accent)
              : _buildDownloadList(selection),
        ),
      ],
    );
  }

  Widget _buildFilterPanel({
    required List<Map<String, dynamic>> selection,
    required List<String> dates,
  }) {
    final sortedBranches = [
      ...widget.zoneBranches,
    ]..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;

          final filters = Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DcFilterBlock(
                icon: Icons.calendar_month_rounded,
                iconColor: widget.accent,
                iconBackground: widget.accent.withValues(alpha: 0.10),
                label: 'Date',
                width: compact ? 250 : 260,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_selectedDate),
                  initialValue: _selectedDate,
                  isExpanded: true,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: _secondaryText,
                  ),
                  decoration: _dcInputDecoration(),
                  items: dates
                      .map(
                        (date) => DropdownMenuItem<String>(
                          value: date,
                          child: Text(
                            _displayDate(date),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: dates.isEmpty
                      ? null
                      : (value) {
                          setState(() => _date = value);
                        },
                ),
              ),
              _DcFilterBlock(
                icon: Icons.storefront_rounded,
                iconColor: _purple,
                iconBackground: _purpleSoft,
                label: 'Branch',
                width: compact ? 290 : 320,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_branch),
                  initialValue: _branch,
                  isExpanded: true,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: _secondaryText,
                  ),
                  decoration: _dcInputDecoration(),
                  items: ['ALL', ...sortedBranches]
                      .map(
                        (branch) => DropdownMenuItem<String>(
                          value: branch,
                          child: Text(
                            branch == 'ALL' ? 'All Zone Branches' : branch,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _branch = value);
                    }
                  },
                ),
              ),
            ],
          );

          final actions = _DcToolbarActions(
            accent: widget.accent,
            fileCount: selection.length,
            onDownload: selection.isEmpty
                ? null
                : () => widget.onDownloadSelection(selection),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                filters,
                const SizedBox(height: 16),
                const Divider(height: 1, color: _border),
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: filters),
              const SizedBox(width: 18),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildDownloadList(List<Map<String, dynamic>> selection) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Scrollbar(
        child: ListView.separated(
          padding: const EdgeInsets.all(22),
          itemCount: selection.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final row = selection[index];

            return _DcDownloadRow(
              accent: widget.accent,
              branchName: _text(row['branch_name']),
              orderDate: _displayDate(_text(row['run_date'])),
              onDownload: () => widget.onDownloadOne(row),
            );
          },
        ),
      ),
    );
  }

  InputDecoration _dcInputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: _softSurface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.accent, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
    );
  }
}

class _DcFilterBlock extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final double width;
  final Widget child;

  const _DcFilterBlock({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.width,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: iconColor.withValues(alpha: 0.14)),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _DownloadCenterState._secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DcToolbarActions extends StatelessWidget {
  final Color accent;
  final int fileCount;
  final VoidCallback? onDownload;

  const _DcToolbarActions({
    required this.accent,
    required this.fileCount,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: _DownloadCenterState._surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _DownloadCenterState._border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 25,
                height: 25,
                decoration: const BoxDecoration(
                  color: _DownloadCenterState._successSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: _DownloadCenterState._success,
                  size: 16,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                '$fileCount file(s) ready',
                style: const TextStyle(
                  color: _DownloadCenterState._pageText,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DcPrimaryDownloadButton extends StatefulWidget {
  final Color accent;
  final bool enabled;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _DcPrimaryDownloadButton({
    required this.accent,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<_DcPrimaryDownloadButton> createState() =>
      _DcPrimaryDownloadButtonState();
}

class _DcPrimaryDownloadButtonState extends State<_DcPrimaryDownloadButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        height: 52,
        decoration: BoxDecoration(
          gradient: enabled
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    widget.accent,
                    Color.lerp(widget.accent, const Color(0xFFDC2626), 0.32) ??
                        widget.accent,
                  ],
                )
              : null,
          color: enabled ? null : _DownloadCenterState._borderStrong,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: widget.accent.withValues(
                      alpha: _hovered ? 0.28 : 0.18,
                    ),
                    blurRadius: _hovered ? 20 : 13,
                    offset: Offset(0, _hovered ? 8 : 5),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, color: Colors.white, size: 19),
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
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

class _DcDownloadRow extends StatefulWidget {
  final Color accent;
  final String branchName;
  final String orderDate;
  final VoidCallback onDownload;

  const _DcDownloadRow({
    required this.accent,
    required this.branchName,
    required this.orderDate,
    required this.onDownload,
  });

  @override
  State<_DcDownloadRow> createState() => _DcDownloadRowState();
}

class _DcDownloadRowState extends State<_DcDownloadRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: _hovered
              ? const Color(0xFFFCFCFF)
              : _DownloadCenterState._surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hovered
                ? widget.accent.withValues(alpha: 0.28)
                : _DownloadCenterState._border,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF0F172A,
              ).withValues(alpha: _hovered ? 0.08 : 0.035),
              blurRadius: _hovered ? 18 : 10,
              offset: Offset(0, _hovered ? 8 : 4),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;

            final details = Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.accent.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Icon(
                    Icons.table_view_rounded,
                    color: widget.accent,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.branchName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _DownloadCenterState._pageText,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 15,
                            color: _DownloadCenterState._secondaryText,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              'Order date: ${widget.orderDate}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _DownloadCenterState._secondaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );

            final status = const _DcReadyChip();

            final download = _DcOutlineDownloadButton(
              accent: widget.accent,
              onPressed: widget.onDownload,
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  details,
                  const SizedBox(height: 14),
                  Row(children: [status, const Spacer(), download]),
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 7, child: details),
                const SizedBox(width: 18),
                Expanded(
                  flex: 2,
                  child: Align(alignment: Alignment.center, child: status),
                ),
                const SizedBox(width: 18),
                Align(alignment: Alignment.centerRight, child: download),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DcReadyChip extends StatelessWidget {
  const _DcReadyChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _DownloadCenterState._successSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _DownloadCenterState._successBorder),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: _DownloadCenterState._success,
            size: 17,
          ),
          SizedBox(width: 7),
          Text(
            'Ready',
            style: TextStyle(
              color: _DownloadCenterState._success,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DcOutlineDownloadButton extends StatefulWidget {
  final Color accent;
  final VoidCallback onPressed;

  const _DcOutlineDownloadButton({
    required this.accent,
    required this.onPressed,
  });

  @override
  State<_DcOutlineDownloadButton> createState() =>
      _DcOutlineDownloadButtonState();
}

class _DcOutlineDownloadButtonState extends State<_DcOutlineDownloadButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
        height: 44,
        decoration: BoxDecoration(
          color: _hovered
              ? widget.accent.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: _hovered
                ? widget.accent
                : widget.accent.withValues(alpha: 0.62),
            width: 1.1,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: widget.accent.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(13),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_rounded, color: widget.accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Download',
                    style: TextStyle(
                      color: widget.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
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

class _BranchQuickView extends StatelessWidget {
  final String branch;
  final String runDate;
  final bool submitted;
  final int additionalCount;
  final int editCount;
  final VoidCallback onOpenDaily;
  final VoidCallback onOpenAdditional;
  final VoidCallback onOpenHistory;

  const _BranchQuickView({
    required this.branch,
    required this.runDate,
    required this.submitted,
    required this.additionalCount,
    required this.editCount,
    required this.onOpenDaily,
    required this.onOpenAdditional,
    required this.onOpenHistory,
  });

  static const Color _dialogBackground = Color(0xFFFCFCFF);
  static const Color _primary = Color(0xFF4F46E5);
  static const Color _primaryDark = Color(0xFF3730A3);
  static const Color _primarySoft = Color(0xFFEEF2FF);
  static const Color _primaryBorder = Color(0xFFC7D2FE);

  static const Color _orange = Color(0xFFF97316);
  static const Color _orangeDark = Color(0xFFEA580C);
  static const Color _orangeSoft = Color(0xFFFFF7ED);
  static const Color _orangeBorder = Color(0xFFFED7AA);

  static const Color _green = Color(0xFF10B981);
  static const Color _greenDark = Color(0xFF047857);
  static const Color _greenSoft = Color(0xFFECFDF5);
  static const Color _greenBorder = Color(0xFFA7F3D0);

  static const Color _blue = Color(0xFF3B82F6);
  static const Color _blueDark = Color(0xFF1D4ED8);
  static const Color _blueSoft = Color(0xFFEFF6FF);
  static const Color _blueBorder = Color(0xFFBFDBFE);

  static const Color _text = Color(0xFF111827);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _border = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    final statusColor = submitted ? _green : _orange;
    final statusDarkColor = submitted ? _greenDark : _orangeDark;
    final statusSoftColor = submitted ? _greenSoft : _orangeSoft;
    final statusBorderColor = submitted ? _greenBorder : _orangeBorder;

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 790),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _dialogBackground,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.92),
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x330F172A),
                  blurRadius: 55,
                  spreadRadius: 3,
                  offset: Offset(0, 24),
                ),
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                const Positioned(
                  top: -130,
                  right: -110,
                  child: _BqvGlowCircle(size: 300, color: Color(0x164F46E5)),
                ),
                const Positioned(
                  bottom: -130,
                  left: -100,
                  child: _BqvGlowCircle(size: 270, color: Color(0x10F97316)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 720;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeader(context),
                          const SizedBox(height: 20),
                          _BqvStatusBanner(
                            submitted: submitted,
                            statusColor: statusColor,
                            statusDarkColor: statusDarkColor,
                            statusSoftColor: statusSoftColor,
                            statusBorderColor: statusBorderColor,
                          ),
                          const SizedBox(height: 18),
                          _buildMetrics(compact),
                          const SizedBox(height: 20),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: _border,
                          ),
                          const SizedBox(height: 18),
                          _buildActions(compact),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C3AED), _primary, _primaryDark],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.70),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _primary.withValues(alpha: 0.30),
                blurRadius: 24,
                spreadRadius: 1,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Icon(
            Icons.storefront_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                branch,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontSize: 24,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  const Text(
                    'Branch overview',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: _primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    _displayDate(runDate),
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _BqvCloseButton(onPressed: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildMetrics(bool compact) {
    final additionalCard = _BqvMetricCard(
      icon: Icons.description_outlined,
      value: additionalCount,
      title: 'Additional Requests',
      accent: _orange,
      accentDark: _orangeDark,
      background: _orangeSoft,
      border: _orangeBorder,
      painterColor: _orange,
    );

    final editsCard = _BqvMetricCard(
      icon: Icons.edit_note_rounded,
      value: editCount,
      title: 'Order Edits',
      accent: _blue,
      accentDark: _blueDark,
      background: _blueSoft,
      border: _blueBorder,
      painterColor: _blue,
    );

    if (compact) {
      return Column(
        children: [additionalCard, const SizedBox(height: 10), editsCard],
      );
    }

    return Row(
      children: [
        Expanded(child: additionalCard),
        const SizedBox(width: 12),
        Expanded(child: editsCard),
      ],
    );
  }

  Widget _buildActions(bool compact) {
    final dailyButton = _BqvActionButton(
      label: 'Open Daily Order',
      icon: Icons.shopping_cart_checkout_rounded,
      onPressed: onOpenDaily,
      type: _BqvActionType.primary,
    );

    final additionalButton = _BqvActionButton(
      label: 'Open Additional',
      icon: Icons.add_box_outlined,
      onPressed: onOpenAdditional,
      type: _BqvActionType.secondary,
    );

    final historyButton = _BqvActionButton(
      label: 'Order History',
      icon: Icons.history_rounded,
      onPressed: onOpenHistory,
      type: _BqvActionType.outlined,
    );

    if (compact) {
      return Column(
        children: [
          SizedBox(width: double.infinity, child: dailyButton),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: additionalButton),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: historyButton),
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 12, child: dailyButton),
        const SizedBox(width: 10),
        Expanded(flex: 10, child: additionalButton),
        const SizedBox(width: 10),
        Expanded(flex: 9, child: historyButton),
      ],
    );
  }
}

class _BqvStatusBanner extends StatelessWidget {
  final bool submitted;
  final Color statusColor;
  final Color statusDarkColor;
  final Color statusSoftColor;
  final Color statusBorderColor;

  const _BqvStatusBanner({
    required this.submitted,
    required this.statusColor,
    required this.statusDarkColor,
    required this.statusSoftColor,
    required this.statusBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 100),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [statusSoftColor, Colors.white.withValues(alpha: 0.88)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusBorderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -20,
            child: _BqvStatusDecoration(color: statusColor),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Icon(
                    submitted
                        ? Icons.check_circle_outline_rounded
                        : Icons.schedule_rounded,
                    color: statusColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        submitted ? 'Order Submitted' : 'Waiting Submission',
                        style: TextStyle(
                          color: statusDarkColor,
                          fontSize: 18,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        submitted
                            ? 'The branch order has been submitted successfully.'
                            : 'The branch data is ready and waiting to be submitted.',
                        style: const TextStyle(
                          color: _BranchQuickView._textSecondary,
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

class _BqvMetricCard extends StatefulWidget {
  final IconData icon;
  final int value;
  final String title;
  final Color accent;
  final Color accentDark;
  final Color background;
  final Color border;
  final Color painterColor;

  const _BqvMetricCard({
    required this.icon,
    required this.value,
    required this.title,
    required this.accent,
    required this.accentDark,
    required this.background,
    required this.border,
    required this.painterColor,
  });

  @override
  State<_BqvMetricCard> createState() => _BqvMetricCardState();
}

class _BqvMetricCardState extends State<_BqvMetricCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) {
        if (!_hovered) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_hovered) {
          setState(() => _hovered = false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        height: 158,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [widget.background, Colors.white],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered
                ? widget.accent.withValues(alpha: 0.40)
                : widget.border,
            width: _hovered ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: _hovered ? 0.13 : 0.065),
              blurRadius: _hovered ? 24 : 15,
              offset: Offset(0, _hovered ? 10 : 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: widget.accent.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Icon(widget.icon, color: widget.accent, size: 21),
                ),
                const Spacer(),
                Icon(
                  Icons.north_east_rounded,
                  color: widget.accent.withValues(alpha: 0.55),
                  size: 17,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.value}',
              style: TextStyle(
                color: widget.accentDark,
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _BranchQuickView._text,
                fontSize: 13,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _BqvMiniTrendPainter(color: widget.painterColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BqvActionType { primary, secondary, outlined }

class _BqvActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final _BqvActionType type;

  const _BqvActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.type,
  });

  @override
  State<_BqvActionButton> createState() => _BqvActionButtonState();
}

class _BqvActionButtonState extends State<_BqvActionButton> {
  bool _hovered = false;

  bool get _isPrimary => widget.type == _BqvActionType.primary;

  bool get _isSecondary => widget.type == _BqvActionType.secondary;

  @override
  Widget build(BuildContext context) {
    final foreground = _isPrimary
        ? Colors.white
        : _BranchQuickView._primaryDark;

    final borderColor = _isPrimary
        ? Colors.transparent
        : _isSecondary
        ? _BranchQuickView._primaryBorder
        : const Color(0xFFB8B4C7);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!_hovered) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_hovered) {
          setState(() => _hovered = false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        height: 54,
        decoration: BoxDecoration(
          gradient: _isPrimary
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: _hovered
                      ? const [Color(0xFF6D5DFB), Color(0xFF4338CA)]
                      : const [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                )
              : null,
          color: _isPrimary
              ? null
              : _isSecondary
              ? _BranchQuickView._primarySoft
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: _isPrimary
              ? [
                  BoxShadow(
                    color: _BranchQuickView._primary.withValues(
                      alpha: _hovered ? 0.34 : 0.24,
                    ),
                    blurRadius: _hovered ? 24 : 17,
                    offset: Offset(0, _hovered ? 10 : 7),
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(
                      0xFF0F172A,
                    ).withValues(alpha: _hovered ? 0.08 : 0.035),
                    blurRadius: _hovered ? 15 : 9,
                    offset: Offset(0, _hovered ? 7 : 4),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: foreground.withValues(alpha: 0.88),
                    size: 12,
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

class _BqvCloseButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _BqvCloseButton({required this.onPressed});

  @override
  State<_BqvCloseButton> createState() => _BqvCloseButtonState();
}

class _BqvCloseButtonState extends State<_BqvCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!_hovered) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_hovered) {
          setState(() => _hovered = false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _hovered
              ? const Color(0xFFF1F5F9)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: _hovered
                ? const Color(0xFFCBD5E1)
                : _BranchQuickView._border,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF0F172A,
              ).withValues(alpha: _hovered ? 0.10 : 0.045),
              blurRadius: _hovered ? 15 : 9,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(13),
            child: const Icon(
              Icons.close_rounded,
              color: Color(0xFF475569),
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}

class _BqvGlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _BqvGlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

class _BqvStatusDecoration extends StatelessWidget {
  final Color color;

  const _BqvStatusDecoration({required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 190,
        height: 170,
        child: CustomPaint(painter: _BqvStatusDecorationPainter(color: color)),
      ),
    );
  }
}

class _BqvStatusDecorationPainter extends CustomPainter {
  final Color color;

  const _BqvStatusDecorationPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.62, size.height * 0.52);

    final circlePaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final radius in <double>[34, 54, 74]) {
      canvas.drawCircle(center, radius, circlePaint);
    }

    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(center.dx - 54, center.dy - 18), 4, dotPaint);

    canvas.drawCircle(Offset(center.dx + 28, center.dy - 50), 3.5, dotPaint);

    canvas.drawCircle(Offset(center.dx + 55, center.dy + 12), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _BqvStatusDecorationPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _BqvMiniTrendPainter extends CustomPainter {
  final Color color;

  const _BqvMiniTrendPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final linePath = Path()
      ..moveTo(0, size.height * 0.74)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.20,
        size.width * 0.34,
        size.height * 0.85,
        size.width * 0.52,
        size.height * 0.54,
      )
      ..cubicTo(
        size.width * 0.68,
        size.height * 0.25,
        size.width * 0.82,
        size.height * 0.65,
        size.width,
        size.height * 0.28,
      );

    final areaPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(areaPath, areaPaint);
    canvas.drawPath(linePath, linePaint);

    final point = Offset(size.width, size.height * 0.28);

    canvas.drawCircle(
      point,
      4.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      point,
      3.2,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _BqvMiniTrendPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ReportLoading extends StatelessWidget {
  final String label;
  const _ReportLoading({required this.label});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: AppColors.primaryColor),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: AppColors.subText)),
      ],
    ),
  );
}

class _DrawerToggle extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onTap;
  const _DrawerToggle({required this.collapsed, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 8,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(
          collapsed
              ? Icons.keyboard_double_arrow_right_rounded
              : Icons.keyboard_double_arrow_left_rounded,
          color: AppColors.primaryColor,
        ),
      ),
    ),
  );
}

class _TinyMetric extends StatelessWidget {
  final String text;
  final Color color;
  const _TinyMetric(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
    ),
  );
}

class _DetailMetric extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _DetailMetric(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.subText),
          ),
        ],
      ),
    ),
  );
}

class _ReportHeading extends StatelessWidget {
  final String title, subtitle;
  const _ReportHeading({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.secondaryColor,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: const TextStyle(color: AppColors.subText, fontSize: 12),
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  final Color color;
  const _EmptyState({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 46,
            color: color.withValues(alpha: .65),
          ),
          const SizedBox(height: 10),
          const Text(
            'No records found for the selected filters.',
            style: TextStyle(color: AppColors.subText),
          ),
        ],
      ),
    ),
  );
}

class _DifferenceCell extends StatelessWidget {
  final dynamic value;
  const _DifferenceCell(this.value);
  @override
  Widget build(BuildContext context) {
    final number = _number(value);
    final color = number == 0
        ? Colors.blueGrey
        : number < 0
        ? Colors.red
        : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _numberText(value),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ZoneOperationOverlay extends StatelessWidget {
  final String label;
  final bool dimBackground;

  const _ZoneOperationOverlay({required this.label, this.dimBackground = true});

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: ColoredBox(
        color: dimBackground
            ? const Color(0x330F172A)
            : const Color(0xffF4F7FB),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .92, end: 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: Opacity(opacity: scale.clamp(0, 1), child: child),
            ),
            child: Container(
              constraints: const BoxConstraints(minWidth: 285, maxWidth: 340),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.primaryColor.withValues(alpha: .18),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x260F172A),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2.7,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff0F172A),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Please wait while the data is synchronized.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xff64748B),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 54,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 12),
          const Text(
            'Could not load Zone Manager Dashboard',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.subText),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );
}

class _ZoneContextData {
  final List<String> effectiveZones;
  final List<String> permanentZones;
  final List<Map<String, dynamic>> delegations;
  final List<Map<String, dynamic>> directory;
  final String currentUserName;
  final bool handoverAvailable;

  const _ZoneContextData({
    required this.effectiveZones,
    required this.permanentZones,
    required this.delegations,
    required this.directory,
    required this.currentUserName,
    required this.handoverAvailable,
  });
}

class _PageDef {
  final IconData icon;
  final String label;
  const _PageDef(this.icon, this.label);
}

class _ColumnDef {
  final String key, label;
  const _ColumnDef(this.key, this.label);
}

InputDecoration _inputDecoration(String hint, IconData icon) => InputDecoration(
  hintText: hint,
  prefixIcon: Icon(icon, size: 19),
  filled: true,
  fillColor: Colors.white,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.5),
  ),
);

String _text(dynamic value) => (value ?? '').toString().trim();
String _key(dynamic value) =>
    _text(value).replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
num _number(dynamic value) =>
    value is num ? value : num.tryParse(_text(value)) ?? 0;
String _numberText(dynamic value) {
  final number = _number(value);
  return number == number.roundToDouble()
      ? '${number.toInt()}'
      : number.toStringAsFixed(2);
}

bool _statusContains(Map<String, dynamic> row, String expected) {
  final status = _text(row['status']).trim().toLowerCase().replaceAll(' ', '_');
  return status.contains(expected.toLowerCase().replaceAll(' ', '_'));
}

bool _isNegativeMaxAdjustment(Map<String, dynamic> row) {
  final type = _text(row['adjustment_type']).toLowerCase();
  return type.contains('decrease') ||
      type.contains('reduce') ||
      type.contains('negative') ||
      type.contains('down') ||
      _number(row['qty']) < 0;
}

bool _isPositiveMaxAdjustment(Map<String, dynamic> row) {
  if (_isNegativeMaxAdjustment(row)) return false;
  final type = _text(row['adjustment_type']).toLowerCase();
  return type.contains('increase') ||
      type.contains('add') ||
      type.contains('positive') ||
      type.contains('up') ||
      _number(row['qty']) > 0;
}

String _latestActivity(List<Map<String, dynamic>> rows, List<String> keys) {
  DateTime? latest;
  for (final row in rows) {
    for (final key in keys) {
      final date = DateTime.tryParse(_text(row[key]));
      if (date != null && (latest == null || date.isAfter(latest))) {
        latest = date;
      }
    }
  }
  if (latest == null) return 'No activity';
  return DateFormat('dd MMM yyyy, hh:mm a').format(latest.toLocal());
}

String _displayDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? value : DateFormat('dd MMM yyyy').format(date);
}

String _displayValue(String key, dynamic value) {
  if (key.contains('date') || key.contains('created')) {
    final date = DateTime.tryParse(_text(value));
    if (date != null) {
      return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
    }
  }
  return _text(value).isEmpty ? '—' : _text(value);
}

String _prettyStatus(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
    .join(' ');
Color _statusColor(String value) {
  final status = value.toLowerCase();
  if (status.contains('reject') ||
      status.contains('out_of_stock') ||
      status.contains('not_transferred')) {
    return Colors.red;
  }
  if (status.contains('done') ||
      status.contains('complete') ||
      status.contains('approved') ||
      status.contains('submitted')) {
    return const Color(0xff16A34A);
  }
  if (status.contains('sent')) return Colors.blue;
  if (status.contains('pending') || status.contains('progress')) {
    return const Color(0xffF59E0B);
  }
  return const Color(0xffF59E0B);
}

double _columnWidth(String key) {
  if (key.contains('name') || key == 'reason' || key == 'note') return 240;
  if (key.contains('branch')) return 150;
  if (key.contains('date') || key.contains('created')) return 145;
  return 115;
}

String _safe(String value) =>
    value.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').replaceAll(' ', '_');

const _kSurface = Color(0xFFFFFFFF);
const _kSurface2 = Color(0xFFF8FAFC);
const _kPageBg = Color(0xFFF1F5F9);
const _kBorder = Color(0xFFE2E8F0);
const _kBorderMd = Color(0xFFCBD5E1);

const _kText = Color(0xFF0F172A);
const _kTextSub = Color(0xFF475569);
const _kTextMute = Color(0xFF94A3B8);

const _kBlue = Color(0xFF3B82F6);
const _kBlueLight = Color(0xFFEFF6FF);
const _kBlueBorder = Color(0xFFBFDBFE);

const _kGreen = Color(0xFF10B981);
const _kGreenLight = Color(0xFFECFDF5);
const _kGreenBorder = Color(0xFFA7F3D0);
const _kGreenDark = Color(0xFF065F46);

const _kOrange = Color(0xFFF97316);
const _kOrangeLight = Color(0xFFFFF7ED);
const _kOrangeBrd = Color(0xFFFED7AA);

const _kRed = Color(0xFFEF4444);
const _kRedLight = Color(0xFFFEF2F2);
const _kRedBorder = Color(0xFFFECACA);

const _kAmber = Color(0xFFF59E0B);
const _kAmberLight = Color(0xFFFFFBEB);
const _kAmberBorder = Color(0xFFFDE68A);

const _kCyan = Color(0xFF0891B2);
const _kCyanLight = Color(0xFFECFEFF);
const _kCyanBorder = Color(0xFFA5F3FC);

const _kPurple = Color(0xFF8B5CF6);
const _kPurpleLight = Color(0xFFF5F3FF);
const _kPurpleBrd = Color(0xFFDDD6FE);

// ─────────────────────────────────────────────────────────────────────────────
//  _HeroMetric  (data class — unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _HeroMetric {
  final String label, value;
  const _HeroMetric(this.label, this.value);
}

// ─────────────────────────────────────────────────────────────────────────────
//  _ModernPageHero
// ─────────────────────────────────────────────────────────────────────────────

class _ModernPageHero extends StatelessWidget {
  final IconData icon;
  final String eyebrow, title, subtitle;
  final Color accent;
  final List<_HeroMetric> metrics;
  final List<Widget> actions;

  const _ModernPageHero({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.metrics,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _kSurface,
        border: const Border(bottom: BorderSide(color: _kBorder)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent.withValues(alpha: .7)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: .3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),

          // Left text block
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Eyebrow
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .08),
                    border: Border.all(color: accent.withValues(alpha: .2)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    eyebrow,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _kText,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _kTextMute),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Metric pills
          for (final m in metrics) ...[
            _HeroPill(metric: m, accent: accent),
            const SizedBox(width: 8),
          ],

          Container(height: 30, width: 1, color: _kBorder),
          const SizedBox(width: 12),

          // Action buttons
          for (final action in actions)
            Padding(padding: const EdgeInsets.only(left: 8), child: action),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final _HeroMetric metric;
  final Color accent;
  const _HeroPill({required this.metric, required this.accent});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .06),
      border: Border.all(color: accent.withValues(alpha: .18)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          metric.value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: accent,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          metric.label.toUpperCase(),
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: _kTextMute,
            letterSpacing: 0.8,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  _Stat  (data class — unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _Stat {
  final IconData icon;
  final String title, value;
  final Color color;
  const _Stat(this.icon, this.title, this.value, this.color);
}

// ─────────────────────────────────────────────────────────────────────────────
//  _StatsRow
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final List<_Stat> cards;
  const _StatsRow({required this.cards});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 90,
    child: Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          Expanded(child: _StatCard(stat: cards[i])),
          if (i < cards.length - 1) const SizedBox(width: 10),
        ],
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  _StatCard
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final _Stat stat;
  const _StatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    // Parse "4 / 10" format
    double? progress;
    String mainNum = stat.value;
    String? denominator;

    if (stat.value.contains('/')) {
      final parts = stat.value.split('/');
      mainNum = parts[0].trim();
      denominator = '/ ${parts[1].trim()}';
      final a = double.tryParse(parts[0].trim()) ?? 0;
      final b = double.tryParse(parts[1].trim()) ?? 1;
      progress = b > 0 ? (a / b).clamp(0.0, 1.0) : 0;
    }

    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Left accent bar
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: stat.color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 11, 11),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: stat.color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(stat.icon, color: stat.color, size: 16),
                ),
                const SizedBox(width: 10),

                // Numbers
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        stat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _kTextMute,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            mainNum,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: _kText,
                              height: 1,
                            ),
                          ),
                          if (denominator != null) ...[
                            const SizedBox(width: 3),
                            Text(
                              denominator,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _kTextMute,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: const Color(0xFFE2E8F0),
                            valueColor: AlwaysStoppedAnimation(stat.color),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
//  _BranchGrid
// ─────────────────────────────────────────────────────────────────────────────

class _BranchGrid extends StatelessWidget {
  final List<Map<String, dynamic>> branches, edits, additional;
  final Map<String, Map<String, dynamic>> submissions;
  final String selectedBranch;
  final ValueChanged<String> onOpen;

  const _BranchGrid({
    required this.branches,
    required this.submissions,
    required this.edits,
    required this.additional,
    required this.selectedBranch,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final visible = branches
        .where(
          (row) =>
              selectedBranch == 'ALL' ||
              _text(row['branch_name']) == selectedBranch,
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            const Text(
              'Branches Ordering Today',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _kText,
              ),
            ),
            const SizedBox(width: 8),
            _CountBadge(count: visible.length),
          ],
        ),
        const SizedBox(height: 10),

        // Grid
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.1, // ← more compact cards
            ),
            itemCount: visible.length,
            itemBuilder: (_, index) {
              final branchName = _text(visible[index]['branch_name']);
              final submitted = submissions.containsKey(_key(branchName));
              final editCount = edits
                  .where((r) => _key(r['branch_name']) == _key(branchName))
                  .length;
              final addCount = additional
                  .where((r) => _key(r['branch_name']) == _key(branchName))
                  .length;

              return _BranchCard(
                branch: branchName,
                submitted: submitted,
                editCount: editCount,
                additionalCount: addCount,
                onTap: () => onOpen(branchName),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BranchCard extends StatelessWidget {
  final String branch;
  final bool submitted;
  final int editCount, additionalCount;
  final VoidCallback onTap;

  const _BranchCard({
    required this.branch,
    required this.submitted,
    required this.editCount,
    required this.additionalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgA = submitted ? const Color(0xFFECFDF5) : _kSurface;
    final Color bgB = submitted ? const Color(0xFFD1FAE5) : _kSurface;
    final Color borderC = submitted ? _kGreenBorder : _kBorder;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          gradient: submitted
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [bgA, bgB],
                )
              : null,
          color: submitted ? null : _kSurface,
          border: Border.all(color: borderC),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: submitted
                  ? _kGreen.withValues(alpha: .12)
                  : const Color(0x06000000),
              blurRadius: submitted ? 12 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: icon + badges
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: submitted ? _kGreenLight : const Color(0xFFF1F5F9),
                    border: Border.all(
                      color: submitted ? _kGreenBorder : _kBorder,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    submitted
                        ? Icons.check_circle_rounded
                        : Icons.store_rounded,
                    size: 13,
                    color: submitted ? _kGreen : _kTextMute,
                  ),
                ),

                const Spacer(),

                // Badges (edits + additional)
                if (additionalCount > 0)
                  _MiniBadge('$additionalCount ADD', _kRed),
                if (additionalCount > 0 && editCount > 0)
                  const SizedBox(width: 4),
                if (editCount > 0) _MiniBadge('$editCount EDITS', _kOrange),
              ],
            ),

            const SizedBox(height: 7),

            // Branch name
            Text(
              branch,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: submitted ? _kGreenDark : _kText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              submitted ? 'ORDER SUBMITTED' : 'WAITING SUBMISSION',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: submitted ? _kGreen : _kTextMute,
              ),
            ),

            const Spacer(),

            // Footer link
            Row(
              children: [
                Icon(
                  Icons.open_in_new_rounded,
                  size: 10,
                  color: submitted ? _kGreen.withValues(alpha: .7) : _kTextMute,
                ),
                const SizedBox(width: 3),
                Text(
                  'Open branch overview',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: submitted
                        ? _kGreen.withValues(alpha: .8)
                        : _kTextMute,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _AdditionalPanel
// ─────────────────────────────────────────────────────────────────────────────

class _AdditionalPanel extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final VoidCallback onViewAll;
  const _AdditionalPanel({required this.rows, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                const Text(
                  'Zone Additional Requests',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kText,
                  ),
                ),
                const SizedBox(width: 8),
                // LIVE badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _kBlueLight,
                    border: Border.all(color: _kBlueBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: _kBlue,
                    ),
                  ),
                ),
                const Spacer(),
                // View All button
                FilledButton(
                  onPressed: onViewAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('View All'),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: _kBorder),

          // Cards
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'No additional requests.',
                      style: TextStyle(color: _kTextMute, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _AdditionalRequestCard(row: rows[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _AdditionalRequestCard
// ─────────────────────────────────────────────────────────────────────────────

class _AdditionalRequestCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _AdditionalRequestCard({required this.row});

  static ({Color bar, Color bg, Color border, Color text}) _theme(String s) {
    final st = s.toLowerCase();
    if (st == 'sent_to_store' || st.contains('sent')) {
      return (bar: _kCyan, bg: _kCyanLight, border: _kCyanBorder, text: _kCyan);
    }
    if (st.contains('reject')) {
      return (bar: _kRed, bg: _kRedLight, border: _kRedBorder, text: _kRed);
    }
    return (
      bar: _kAmber,
      bg: _kAmberLight,
      border: _kAmberBorder,
      text: _kAmber,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _text(row['status']);
    final t = _theme(status);

    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(9),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: t.bar,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(9),
                  bottomLeft: Radius.circular(9),
                ),
                boxShadow: [
                  BoxShadow(color: t.bar.withValues(alpha: .35), blurRadius: 6),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        // Item code
                        Text(
                          _text(row['item_code']),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _kBlue,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Item name
                        Expanded(
                          child: Text(
                            _text(row['item_name']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _kText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: t.bg,
                            border: Border.all(color: t.border),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _prettyStatus(status).toUpperCase(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                              color: t.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Branch row
                    Row(
                      children: [
                        const Icon(
                          Icons.store_rounded,
                          size: 10,
                          color: _kTextMute,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _text(row['branch_name']),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kTextSub,
                            ),
                          ),
                        ),
                        // Req badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kRedLight,
                            border: Border.all(color: _kRedBorder),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'REQ: ${_numberText(row['request_qty'])}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: _kRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),

                    // Metrics row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _kSurface2,
                        border: Border.all(color: _kBorder),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        children: [
                          _InfoCell('BR STOCK', row['branch_stock']),
                          _InfoCell('STR STOCK', row['store_stock']),
                          _InfoCell('SALES', row['sales_45d']),
                          _InfoCell('REORDER', row['final_reorder_qty']),
                          _InfoCell('INVENT', row['inventory_qty']),
                          _InfoCell(
                            'FULFILL',
                            row['fulfilled_qty'],
                            isLast: true,
                          ),
                        ],
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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _InfoCell
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCell extends StatelessWidget {
  final String label;
  final dynamic value;
  final bool isLast;
  const _InfoCell(this.label, this.value, {this.isLast = false});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      decoration: isLast
          ? null
          : const BoxDecoration(
              border: Border(right: BorderSide(color: _kBorder)),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: _kTextMute,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _numberText(value),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _kTextSub,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  _MiniBadge
// ─────────────────────────────────────────────────────────────────────────────

class _MiniBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniBadge(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      border: Border.all(color: color.withValues(alpha: .28)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: color,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  _StatusChip
// ─────────────────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final normalized = status.toLowerCase();
    final submitted = normalized.contains('submitted');
    final pending =
        normalized.contains('pending') || normalized.contains('progress');
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: submitted || pending ? .13 : .09),
        border: Border.all(
          color: color.withValues(alpha: submitted || pending ? .48 : .30),
          width: submitted || pending ? 1.2 : 1,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: submitted || pending
            ? [
                BoxShadow(
                  color: color.withValues(alpha: .10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Text(
        _prettyStatus(status).toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.65,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _CountBadge  (helper — internal)
// ─────────────────────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: _kSurface2,
      border: Border.all(color: _kBorder),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$count',
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _kTextMute,
      ),
    ),
  );
}
