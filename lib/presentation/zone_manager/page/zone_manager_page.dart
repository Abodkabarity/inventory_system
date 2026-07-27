// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, unused_element

import 'dart:html' as html;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
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
import '../../orders/widgets/orders_grid_controller.dart';
import '../../orders/widgets/orders_table.dart';

class ZoneManagerPage extends StatefulWidget {
  final String runDate;
  final String zoneName;

  const ZoneManagerPage({
    super.key,
    required this.runDate,
    required this.zoneName,
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
  final int _dailyTotal = 0;
  int _dailyPageIndex = 0;
  static const int _dailyPageSize = 100;
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
  List<Map<String, dynamic>> _mismatch = const [];
  List<Map<String, dynamic>> _maxAdj = const [];
  List<Map<String, dynamic>> _dailyExports = const [];
  List<Map<String, dynamic>> _nonReceivedExports = const [];
  List<Map<String, dynamic>> _edits = const [];
  List<StockCheckTask> _stockChecks = const [];
  bool _stockCheckLoading = false;
  String? _stockCheckError;
  String? _selectedStockCheckBatchId;
  Map<String, Map<String, dynamic>> _submissions = const {};

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
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branchData = await _client
          .from('branches')
          .select('branch_name,zone')
          .eq('is_active', true)
          .eq('zone', widget.zoneName)
          .order('branch_name');
      final branches = List<Map<String, dynamic>>.from(branchData);
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
      ]);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _additional = result[0];
        _dailyExports = result[1];
        _nonReceivedExports = result[2];
        _edits = result[3];
        _submissions = result[4];
        if (_selectedBranch != 'ALL' && !names.contains(_selectedBranch)) {
          _selectedBranch = 'ALL';
        }
        _loading = false;
      });
      if (_page == 3) await _loadDailyBranch();
      if (_page == 6) await _loadStockChecks();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
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

  Future<void> _loadDailyPage({bool reset = false}) => _loadDailyBranch();

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

  Future<List<Map<String, dynamic>>> _loadMismatch(
    List<String> branches,
  ) => _fetchPreviewByBranch(
    table: 'stk_mismatch',
    branchColumn: 'branch_name',
    branches: branches,
    columns:
        'id,branch_name,item_code,item_name,system_stock,actual_stock,diff,update_date,created_at',
    orderBy: 'update_date',
  );

  Future<List<Map<String, dynamic>>> _loadMaxAdj(
    List<String> branches,
  ) => _fetchPreviewByBranch(
    table: 'max_adj',
    branchColumn: 'branch_name',
    branches: branches,
    columns:
        'id,branch_name,item_code,item_name,current_demand_30d,max_adjustment_30d,adjustment_type,qty,reason,update_date,added_by,created_at,end_date',
    orderBy: 'created_at',
  );

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

  Future<List<Map<String, dynamic>>> _loadEdits(List<String> branches) =>
      _fetchByBranch(
        table: 'order_edits',
        branchColumn: 'branch_name',
        branches: branches,
        columns:
            'branch_name,item_code,item_name,old_qty,new_qty,diff,created_at',
        runDateColumn: 'run_date',
      );

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
        const batchSize = 5000;
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
          output.addAll(data.map(StockCheckTask.fromMap));
          if (data.length < batchSize) break;
          offset += batchSize;
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
  }) async {
    if (branches.isEmpty) return const [];
    final output = <Map<String, dynamic>>[];
    for (final chunk in _chunks(branches, 20)) {
      var offset = 0;
      const batch = 5000;
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
        final data = List<Map<String, dynamic>>.from(
          await query.range(offset, offset + batch - 1),
        );
        output.addAll(data);
        if (data.length < batch) break;
        offset += batch;
      }
    }
    return output;
  }

  Future<List<Map<String, dynamic>>> _fetchPreviewByBranch({
    required String table,
    required String branchColumn,
    required List<String> branches,
    required String columns,
    String? orderBy,
  }) async {
    if (branches.isEmpty) return const [];
    final output = <Map<String, dynamic>>[];
    for (final chunk in _chunks(branches, 20)) {
      dynamic query = _client
          .from(table)
          .select(columns)
          .inFilter(branchColumn, chunk);
      if (orderBy != null) {
        query = query.order(orderBy, ascending: false);
      }
      output.addAll(List<Map<String, dynamic>>.from(await query.range(0, 499)));
    }
    return output;
  }

  Future<void> _changePage(int page) async {
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
    if (page != 1 && page != 2) return;
    if (page == 1 && _mismatch.isNotEmpty) return;
    if (page == 2 && _maxAdj.isNotEmpty) return;
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
        ..download = '${title}_${_safe(widget.zoneName)}.zip'
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
      titleRange.setText('$title • ${widget.zoneName}');
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
        ..download = '${_safe(title)}_${_safe(widget.zoneName)}_$date.xlsx'
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
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryColor),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xffF4F7FB),
        body: _ErrorView(message: _error!, onRetry: _load),
      );
    }
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
                      zoneName: widget.zoneName,
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
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryColor,
                  ),
                ),
              ),
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
          zoneName: widget.zoneName,
          runDate: widget.runDate,
          branches: _branches.map((row) => _text(row['branch_name'])).toList(),
          selectedBranch: _selectedBranch,
          allowAllBranches: _page != 3,
          search: _search,
          onBranchChanged: _onBranchChanged,
          onSearchChanged: _onSearchChanged,
          onRefresh: _load,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: switch (_page) {
              0 => _dashboard(),
              1 => _mismatchPage(),
              2 => _maxPage(),
              3 => _buildDailyOrderView(),
              4 => _additionalPage(),
              5 => _orderEditsPage(),
              6 => _stockCheckPage(),
              7 => _nonReceivedPage(),
              _ => _exportsPage(),
            },
          ),
        ),
      ],
    );
  }

  Widget _dashboard() {
    final submitted = _branches
        .where(
          (branch) => _submissions.containsKey(_key(branch['branch_name'])),
        )
        .length;
    final rejected = _additional
        .where((row) => _text(row['status']).toLowerCase().contains('reject'))
        .length;
    final pending = _additional
        .where((row) => _text(row['status']).toLowerCase().contains('pending'))
        .length;
    final sent = _additional
        .where((row) => _text(row['status']).toLowerCase() == 'sent_to_store')
        .length;
    return Column(
      children: [
        _ModernPageHero(
          icon: Icons.hub_rounded,
          eyebrow: 'ZONE OPERATIONS',
          title: '${widget.zoneName} Control Center',
          subtitle:
              'Live branch activity for ${_displayDate(widget.runDate)} • select any branch to inspect its operation.',
          accent: AppColors.primaryColor,
          metrics: [
            _HeroMetric('Branches', '${_branches.length}'),
            _HeroMetric('Submitted', '$submitted'),
            _HeroMetric('Order Edits', '${_edits.length}'),
          ],
          actions: [
            OutlinedButton.icon(
              onPressed: () => _changePage(5),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('View Edits'),
            ),
            FilledButton.icon(
              onPressed: () => _changePage(3),
              icon: const Icon(Icons.shopping_cart_checkout_rounded),
              label: const Text('Open Daily Order'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatsRow(
          cards: [
            _Stat(
              Icons.store_rounded,
              'Zone Branches',
              '${_branches.length}',
              Colors.deepPurple,
            ),
            _Stat(
              Icons.inventory_rounded,
              'Submitted Orders',
              '$submitted / ${_branches.length}',
              Colors.green,
            ),
            _Stat(
              Icons.add_box_rounded,
              'Additional Today',
              '${_additional.length}',
              Colors.orange,
            ),
            _Stat(
              Icons.cancel_rounded,
              'Rejected Additional',
              '$rejected',
              Colors.redAccent,
            ),
            _Stat(
              Icons.hourglass_bottom_rounded,
              'Pending / Sent To Store',
              '$pending / $sent',
              Colors.deepOrange,
              subtitle: 'Additional workflow',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                SizedBox(
                  width: constraints.maxWidth * .44,
                  child: _BranchGrid(
                    branches: _branches,
                    submissions: _submissions,
                    edits: _edits,
                    additional: _additional,
                    selectedBranch: _selectedBranch,
                    onOpen: _openBranch,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AdditionalPanel(
                    rows: _filtered(_additional, 'branch_name'),
                    onViewAll: () => _changePage(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mismatchPage() {
    if (_reportLoading && _mismatch.isEmpty) {
      return const _ReportLoading(label: 'Loading mismatch report…');
    }
    final rows = _filtered(_mismatch, 'branch_name')..sort(_compareBranchItem);
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('system_stock', 'System Stock'),
      _ColumnDef('actual_stock', 'Actual Stock'),
      _ColumnDef('diff', 'Diff'),
      _ColumnDef('update_date', 'Updated'),
    ];
    return _ReportPage(
      title: 'Mismatch Report',
      subtitle: 'Current stock differences for branches in ${widget.zoneName}.',
      accent: const Color(0xffF97316),
      rows: rows,
      columns: columns,
      kpis: [
        _ReportKpi(
          Icons.inventory_2_outlined,
          'Total Mismatches',
          '${rows.length}',
          'Items with stock variance',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.trending_down_rounded,
          'Negative Diff',
          '${rows.where((row) => _number(row['diff']) < 0).length}',
          'Lower actual stock',
          const Color(0xffEF4444),
        ),
        _ReportKpi(
          Icons.trending_up_rounded,
          'Positive Diff',
          '${rows.where((row) => _number(row['diff']) > 0).length}',
          'Higher actual stock',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.schedule_rounded,
          'Last Updated',
          _latestActivity(rows, const ['update_date', 'created_at']),
          'Latest data refresh time',
          const Color(0xff7C3AED),
        ),
      ],
      onExport: () => _exportExcel('Mismatch_Report', rows, columns),
    );
  }

  Widget _maxPage() {
    if (_reportLoading && _maxAdj.isEmpty) {
      return const _ReportLoading(label: 'Loading max adjustments…');
    }
    final rows = _filtered(_maxAdj, 'branch_name')..sort(_compareBranchItem);
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('current_demand_30d', 'Demand'),
      _ColumnDef('max_adjustment_30d', 'Max Adj'),
      _ColumnDef('adjustment_type', 'Type'),
      _ColumnDef('qty', 'Qty'),
      _ColumnDef('reason', 'Reason'),
      _ColumnDef('update_date', 'Date'),
      _ColumnDef('added_by', 'Added By'),
    ];
    return _ReportPage(
      title: 'Max Adjustment',
      subtitle: 'All active maximum-stock adjustments for zone branches.',
      accent: const Color(0xffF97316),
      rows: rows,
      columns: columns,
      kpis: [
        _ReportKpi(
          Icons.tune_rounded,
          'Total Adjustments',
          '${rows.length}',
          'Active maximum changes',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.add_chart_rounded,
          'Increased Max',
          '${rows.where(_isPositiveMaxAdjustment).length}',
          'Upward stock adjustments',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.trending_down_rounded,
          'Reduced Max',
          '${rows.where(_isNegativeMaxAdjustment).length}',
          'Downward stock adjustments',
          const Color(0xffEF4444),
        ),
        _ReportKpi(
          Icons.schedule_rounded,
          'Last Updated',
          _latestActivity(rows, const ['update_date', 'created_at']),
          'Latest adjustment activity',
          const Color(0xff7C3AED),
        ),
      ],
      onExport: () => _exportExcel('Max_Adjustment', rows, columns),
    );
  }

  Widget _buildDailyOrderView() {
    if (_dailyLoading && _dailyRows.isEmpty) {
      return const _ReportLoading(label: 'Loading daily order...');
    }
    if (_dailyError != null && _dailyRows.isEmpty) {
      return _DailyOrderError(message: _dailyError!, onRetry: _loadDailyBranch);
    }
    final query = _query.trim().toLowerCase();
    final rows = query.isEmpty
        ? _dailyRows
        : _dailyRows
              .where(
                (row) =>
                    row.itemCode.toLowerCase().contains(query) ||
                    row.itemName.toLowerCase().contains(query) ||
                    (row.barcode ?? '').toLowerCase().contains(query) ||
                    (row.category ?? '').toLowerCase().contains(query),
              )
              .toList(growable: false);
    final exportRows = query.isEmpty
        ? _dailyRawRows
        : _dailyRawRows
              .where(
                (row) => row.values.any(
                  (value) => _text(value).toLowerCase().contains(query),
                ),
              )
              .toList(growable: false);
    const exportColumns = [
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('branch_stock', 'Branch Stock'),
      _ColumnDef('mismatch_stock', 'Mismatch Stock'),
      _ColumnDef('store_stock', 'Store Stock'),
      _ColumnDef('pending_stock_received', 'Pending Received'),
      _ColumnDef('demand_for_30_days', 'Demand 30D'),
      _ColumnDef('reorder_qty_num', 'Reorder Qty'),
      _ColumnDef('final_reorder_qty_store_stock_gt_0', 'Final Order'),
      _ColumnDef('category', 'Category'),
      _ColumnDef('barcode', 'Barcode'),
    ];
    const gridColumns = [
      'row_no',
      'item_code',
      'item_name',
      'branch_stock',
      'mismatch_stock',
      'store_stock',
      'pending_stock_received',
      'demand_for_30_days',
      'reorder_point_min',
      'reorder_max',
      'reorder_qty',
      'final_reorder_qty_store_stock_gt_0',
      'category',
      'barcode',
    ];
    final finalOrder = rows.fold<num>(
      0,
      (sum, row) => sum + (num.tryParse(row.finalReorderQtyStoreStockGt0) ?? 0),
    );
    return Column(
      children: [
        _ModernPageHero(
          icon: Icons.shopping_cart_checkout_rounded,
          eyebrow: 'DAILY OPERATIONS',
          title: _selectedBranch,
          subtitle:
              '${_displayDate(widget.runDate)}  •  ${rows.length} order lines  •  Read-only zone view',
          accent: AppColors.primaryColor,
          metrics: [
            _HeroMetric('Items', '${rows.length}'),
            _HeroMetric('Final Order', finalOrder.toStringAsFixed(0)),
            _HeroMetric(
              'Mismatch',
              '${rows.where((row) => row.mismatchStock != 0).length}',
            ),
          ],
          actions: [
            OutlinedButton.icon(
              onPressed: () => _changePage(8),
              icon: const Icon(Icons.history_rounded),
              label: const Text('Order History'),
            ),
            FilledButton.icon(
              onPressed: exportRows.isEmpty
                  ? null
                  : () => _exportExcel(
                      'Daily_Order_${_safe(_selectedBranch)}',
                      exportRows,
                      exportColumns,
                    ),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Export Excel'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff0F2942).withValues(alpha: .06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: OrdersTable(
              rows: rows,
              isLoading: _dailyLoading,
              orderedColumns: gridColumns,
              columnWidths: _dailyColumnWidths,
              finalEdits: const {},
              onTapFinalReorder: (_) {},
              additionalEdits: const {},
              sentAdditionalQtyByItemCode: const {},
              onTapAdditionalRequest: (_) {},
              isSubmitted: true,
              canEditFinalReorder: false,
              showAdditionalRowActions: false,
              submitStartHour: 0,
              submitEndHour: 23,
              controller: _dailyGridController.controller,
              gridController: _dailyGridController,
              onColumnResized: (key, width) {
                _dailyColumnWidths[key] = width;
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _dailyPage() {
    if (_dailyLoading && _dailyPageRows.isEmpty) {
      return const _ReportLoading(label: 'Loading daily order...');
    }
    if (_dailyError != null && _dailyPageRows.isEmpty) {
      return _DailyOrderError(
        message: _dailyError!,
        onRetry: () => _loadDailyPage(reset: true),
      );
    }
    final rows = _dailyPageRows;
    const columns = [
      _ColumnDef('branch', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('branch_stock', 'Branch Stock'),
      _ColumnDef('mismatch_stock', 'Mismatch Stock'),
      _ColumnDef('store_stock', 'Store Stock'),
      _ColumnDef('pending_stock_received', 'Pending Received'),
      _ColumnDef('reorder_qty_num', 'Reorder Qty'),
      _ColumnDef('final_reorder_qty_store_stock_gt_0', 'Final Order'),
      _ColumnDef('category', 'Category'),
    ];
    return _ReportPage(
      title: 'Daily Order',
      subtitle:
          'Business date ${_displayDate(widget.runDate)} • ${rows.length} lines.',
      accent: AppColors.primaryColor,
      rows: rows,
      columns: columns,
      onExport: () => _exportExcel(
        'Daily_Order_Page_${_dailyPageIndex + 1}',
        rows,
        columns,
      ),
      footer: _DailyPagination(
        branch: _selectedBranch,
        runDate: widget.runDate,
        total: _dailyTotal,
        pageIndex: _dailyPageIndex,
        pageSize: _dailyPageSize,
        loading: _dailyLoading,
        onPrevious: _dailyPageIndex == 0 || _dailyLoading
            ? null
            : () {
                setState(() => _dailyPageIndex--);
                _loadDailyPage();
              },
        onNext:
            ((_dailyPageIndex + 1) * _dailyPageSize >= _dailyTotal) ||
                _dailyLoading
            ? null
            : () {
                setState(() => _dailyPageIndex++);
                _loadDailyPage();
              },
        onHistory: () => _changePage(6),
      ),
    );
  }

  Widget _additionalPage() {
    final rows = _filtered(_additional, 'branch_name');
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('request_qty', 'Requested'),
      _ColumnDef('inventory_qty', 'Inventory Confirm'),
      _ColumnDef('fulfilled_qty', 'Store Supply'),
      _ColumnDef('branch_stock', 'Branch Stock'),
      _ColumnDef('store_stock', 'Store Stock'),
      _ColumnDef('status', 'Status'),
      _ColumnDef('created_at', 'Created'),
    ];
    return _ReportPage(
      title: 'Additional Orders',
      subtitle:
          'Requests and fulfillment status for the selected zone branches.',
      accent: AppColors.primaryColor,
      rows: rows,
      columns: columns,
      kpis: [
        _ReportKpi(
          Icons.receipt_long_rounded,
          'Total Requests',
          '${rows.length}',
          'Additional order lines',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.hourglass_top_rounded,
          'Pending',
          '${rows.where((row) => _statusContains(row, 'pending')).length}',
          'Awaiting action',
          const Color(0xffF59E0B),
        ),
        _ReportKpi(
          Icons.local_shipping_outlined,
          'Sent To Store',
          '${rows.where((row) => _statusContains(row, 'sent_to_store')).length}',
          'Approved and forwarded',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.cancel_outlined,
          'Rejected',
          '${rows.where((row) => _statusContains(row, 'reject')).length}',
          'Rejected requests',
          const Color(0xffEF4444),
        ),
      ],
      onExport: () => _exportExcel('Additional_Orders', rows, columns),
    );
  }

  Widget _orderEditsPage() {
    final rows = _filtered(_edits, 'branch_name')..sort(_compareBranchItem);
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('old_qty', 'Original Qty'),
      _ColumnDef('new_qty', 'Edited Qty'),
      _ColumnDef('diff', 'Difference'),
      _ColumnDef('created_at', 'Edited At'),
    ];
    return _ReportPage(
      title: 'Order Edits',
      subtitle:
          'Every daily-order quantity change made by branches on ${_displayDate(widget.runDate)}.',
      accent: const Color(0xff2563EB),
      rows: rows,
      columns: columns,
      kpis: [
        _ReportKpi(
          Icons.edit_note_rounded,
          'Total Edits',
          '${rows.length}',
          'Changed daily-order lines',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.trending_up_rounded,
          'Quantity Increased',
          '${rows.where((row) => _number(row['diff']) > 0).length}',
          'Edits above original qty',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.trending_down_rounded,
          'Quantity Reduced',
          '${rows.where((row) => _number(row['diff']) < 0).length}',
          'Edits below original qty',
          const Color(0xffEF4444),
        ),
        _ReportKpi(
          Icons.schedule_rounded,
          'Last Edited',
          _latestActivity(rows, const ['created_at']),
          'Latest branch edit time',
          const Color(0xff7C3AED),
        ),
      ],
      onExport: () => _exportExcel('Order_Edits', rows, columns),
    );
  }

  Future<void> _exportStockChecks(
    List<StockCheckTask> rows,
    String title,
  ) async {
    if (rows.isEmpty) return;
    setState(() => _busy = true);
    try {
      await StockCheckExcelExporter.export(rows: rows, title: title);
    } catch (error) {
      _message('Stock Check export failed: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stockCheckPage() {
    if (_stockCheckLoading && _stockChecks.isEmpty) {
      return const _ReportLoading(label: 'Loading Stock Check results...');
    }
    if (_stockCheckError != null && _stockChecks.isEmpty) {
      return _DailyOrderError(
        title: 'Stock Check could not be loaded',
        message: _stockCheckError!,
        onRetry: _loadStockChecks,
      );
    }
    final branchRows = _stockChecks
        .where(
          (row) =>
              _selectedBranch == 'ALL' || row.branchName == _selectedBranch,
        )
        .toList(growable: false);
    if (_selectedStockCheckBatchId == null) {
      return _stockCheckProjectsOverview(branchRows);
    }
    final query = _query.trim().toLowerCase();
    final rows = branchRows
        .where((row) {
          if (row.batchId != _selectedStockCheckBatchId) return false;
          if (query.isEmpty) return true;
          return row.title.toLowerCase().contains(query) ||
              row.branchName.toLowerCase().contains(query) ||
              row.itemCode.toLowerCase().contains(query) ||
              row.itemName.toLowerCase().contains(query) ||
              row.status.toLowerCase().contains(query) ||
              row.submittedByName.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final tableRows = rows
        .map(
          (row) => <String, dynamic>{
            'title': row.title,
            'branch_name': row.branchName,
            'item_code': row.itemCode,
            'item_name': row.itemName,
            'system_qty': row.systemQty,
            'actual_qty': row.actualQty,
            'diff': row.variance,
            'status': row.isSubmitted ? 'Submitted' : 'Pending',
            'submitted_by_name': row.submittedByName,
            'submitted_at': row.submittedAt?.toIso8601String(),
          },
        )
        .toList(growable: false);
    const columns = [
      _ColumnDef('title', 'Project'),
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('system_qty', 'System Qty'),
      _ColumnDef('actual_qty', 'Actual Qty'),
      _ColumnDef('diff', 'Variance'),
      _ColumnDef('status', 'Status'),
      _ColumnDef('submitted_by_name', 'Submitted By'),
      _ColumnDef('submitted_at', 'Submitted At'),
    ];
    final submitted = rows.where((row) => row.isSubmitted).length;
    final pending = rows.length - submitted;
    final mismatches = rows
        .where((row) => (row.variance ?? 0).abs() > .01)
        .length;
    final entireProjectRows = _stockChecks
        .where((row) => row.batchId == _selectedStockCheckBatchId)
        .toList(growable: false);
    final projectTitle = entireProjectRows.isEmpty
        ? 'Stock Check Project'
        : entireProjectRows.first.title;
    return _ReportPage(
      title: projectTitle,
      subtitle:
          'Stock Check project details • ${rows.length} visible item checks.',
      accent: const Color(0xff0EA5E9),
      rows: tableRows,
      columns: columns,
      kpis: [
        _ReportKpi(
          Icons.folder_copy_outlined,
          'Items',
          '${rows.length}',
          'Items in this project',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.task_alt_rounded,
          'Submitted',
          '$submitted',
          'Completed item checks',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.pending_actions_rounded,
          'Pending',
          '$pending',
          'Awaiting branch completion',
          const Color(0xffF59E0B),
        ),
        _ReportKpi(
          Icons.warning_amber_rounded,
          'Stock Variances',
          '$mismatches',
          'Submitted items with variance',
          const Color(0xffEF4444),
        ),
      ],
      extraActions: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _selectedStockCheckBatchId = null),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to Projects'),
        ),
        OutlinedButton.icon(
          onPressed: entireProjectRows.isEmpty
              ? null
              : () => _exportStockChecks(
                  entireProjectRows,
                  'Stock_Check_${_safe(projectTitle)}_All_Branches',
                ),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Download Full Project'),
        ),
      ],
      exportLabel: _selectedBranch == 'ALL'
          ? 'Download Visible'
          : 'Download Branch',
      onExport: () => _exportStockChecks(
        rows,
        _selectedBranch == 'ALL'
            ? 'Stock_Check_${_safe(widget.zoneName)}_Visible'
            : 'Stock_Check_${_safe(projectTitle)}_${_safe(_selectedBranch)}',
      ),
    );
  }

  Widget _stockCheckProjectsOverview(List<StockCheckTask> branchRows) {
    final query = _query.trim().toLowerCase();
    final groups = <String, List<StockCheckTask>>{};
    for (final row in branchRows) {
      groups.putIfAbsent(row.batchId, () => []).add(row);
    }
    final projects =
        groups.entries
            .map(
              (entry) => _StockCheckProjectSummary(
                batchId: entry.key,
                rows: entry.value,
              ),
            )
            .where((project) {
              if (query.isEmpty) return true;
              return project.title.toLowerCase().contains(query) ||
                  project.branches.any(
                    (branch) => branch.toLowerCase().contains(query),
                  ) ||
                  project.rows.any(
                    (row) =>
                        row.itemCode.toLowerCase().contains(query) ||
                        row.itemName.toLowerCase().contains(query),
                  );
            })
            .toList()
          ..sort((left, right) => right.sentAt.compareTo(left.sentAt));
    final visibleRows = projects
        .expand((project) => project.rows)
        .toList(growable: false);
    final submitted = visibleRows.where((row) => row.isSubmitted).length;
    final pending = visibleRows.length - submitted;
    final variances = visibleRows
        .where((row) => (row.variance ?? 0).abs() > .01)
        .length;
    return Column(
      children: [
        _ModernPageHero(
          icon: Icons.folder_copy_outlined,
          eyebrow: 'STOCK CHECK CENTER',
          title: 'Stock Check Projects',
          subtitle:
              '${widget.zoneName} • ${_selectedBranch == 'ALL' ? 'All branches' : _selectedBranch} • Open a project to view its item details.',
          accent: const Color(0xff0EA5E9),
          metrics: const [],
          actions: [
            FilledButton.icon(
              onPressed: branchRows.isEmpty
                  ? null
                  : () => _exportStockChecks(
                      branchRows,
                      _selectedBranch == 'ALL'
                          ? 'Stock_Check_${_safe(widget.zoneName)}_All_Projects'
                          : 'Stock_Check_${_safe(_selectedBranch)}_All_Projects',
                    ),
              icon: const Icon(Icons.download_rounded),
              label: Text(
                _selectedBranch == 'ALL'
                    ? 'Download All Zone'
                    : 'Download Branch Projects',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ReportKpiStrip(
          kpis: [
            _ReportKpi(
              Icons.folder_copy_outlined,
              'Projects',
              '${projects.length}',
              'Visible Stock Check projects',
              const Color(0xff2563EB),
            ),
            _ReportKpi(
              Icons.task_alt_rounded,
              'Submitted',
              '$submitted',
              'Completed item checks',
              const Color(0xff16A34A),
            ),
            _ReportKpi(
              Icons.pending_actions_rounded,
              'Pending',
              '$pending',
              'Awaiting completion',
              const Color(0xffF59E0B),
            ),
            _ReportKpi(
              Icons.warning_amber_rounded,
              'Stock Variances',
              '$variances',
              'Items with stock variance',
              const Color(0xffEF4444),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: projects.isEmpty
              ? const _EmptyState(color: Color(0xff0EA5E9))
              : GridView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 430,
                    mainAxisExtent: 238,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: projects.length,
                  itemBuilder: (context, index) => _StockCheckProjectCard(
                    project: projects[index],
                    onOpen: () => setState(
                      () =>
                          _selectedStockCheckBatchId = projects[index].batchId,
                    ),
                    onDownload: () => _exportStockChecks(
                      projects[index].rows,
                      'Stock_Check_${_safe(projects[index].title)}',
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _nonReceivedPage() {
    return _DownloadCenter(
      title: 'Non Received',
      subtitle:
          'Download the prepared Non Received Excel files. No heavy item table is loaded.',
      rows: _nonReceivedExports,
      zoneBranches: _branches.map((row) => _text(row['branch_name'])).toList(),
      accent: Colors.redAccent,
      onDownloadOne: (row) => _downloadExport(row, nonReceived: true),
      onDownloadSelection: (rows) =>
          _downloadExportBatch(rows, nonReceived: true),
    );
  }

  Widget _exportsPage() {
    return _DownloadCenter(
      title: 'Daily Order History',
      subtitle:
          'Choose an order date and download one branch or one ZIP for every branch in the zone.',
      rows: _dailyExports,
      zoneBranches: _branches.map((row) => _text(row['branch_name'])).toList(),
      accent: AppColors.primaryColor,
      onDownloadOne: (row) => _downloadExport(row, nonReceived: false),
      onDownloadSelection: (rows) =>
          _downloadExportBatch(rows, nonReceived: false),
    );
  }
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
                  'Inventory Management',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                    style: const TextStyle(
                      color: AppColors.secondaryColor,
                      fontSize: 11,
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
  final TextEditingController search;
  final ValueChanged<String> onBranchChanged, onSearchChanged;
  final VoidCallback onRefresh;
  final bool allowAllBranches;

  const _ZoneHeader({
    required this.title,
    required this.zoneName,
    required this.runDate,
    required this.branches,
    required this.selectedBranch,
    required this.allowAllBranches,
    required this.search,
    required this.onBranchChanged,
    required this.onSearchChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
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
                  '$zoneName Zone • ${_displayDate(runDate)}',
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontSize: 12,
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
              items: [if (allowAllBranches) 'ALL', ...branches]
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
          const SizedBox(width: 10),
          SizedBox(
            width: 290,
            child: TextField(
              controller: search,
              onChanged: onSearchChanged,
              decoration: _inputDecoration(
                'Search branch, item code, or name…',
                Icons.search_rounded,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: onRefresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final List<_Stat> cards;
  const _StatsRow({required this.cards});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < cards.length; i++) ...[
        Expanded(child: _StatCard(stat: cards[i])),
        if (i < cards.length - 1) const SizedBox(width: 10),
      ],
    ],
  );
}

class _StatCard extends StatelessWidget {
  final _Stat stat;
  const _StatCard({required this.stat});
  @override
  Widget build(BuildContext context) => Container(
    height: 100,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          blurRadius: 18,
          color: Colors.black.withValues(alpha: .05),
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: stat.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(stat.icon, color: stat.color, size: 25),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                stat.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                stat.value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (stat.subtitle != null)
                Text(
                  stat.subtitle!,
                  style: const TextStyle(fontSize: 9, color: AppColors.subText),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundWidget,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Branches Ordering Today',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.55,
              ),
              itemCount: visible.length,
              itemBuilder: (_, index) {
                final branch = _text(visible[index]['branch_name']);
                final submitted = submissions.containsKey(_key(branch));
                final editCount = edits
                    .where((row) => _key(row['branch_name']) == _key(branch))
                    .length;
                final additionalCount = additional
                    .where((row) => _key(row['branch_name']) == _key(branch))
                    .length;
                return InkWell(
                  onTap: () => onOpen(branch),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: submitted
                          ? Colors.greenAccent.shade100
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 14,
                          color: Colors.black.withValues(alpha: .06),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              submitted ? Icons.check_circle : Icons.store,
                              color: submitted
                                  ? Colors.green
                                  : AppColors.primaryColor,
                            ),
                            const Spacer(),
                            if (additionalCount > 0)
                              _MiniBadge('$additionalCount req', Colors.red),
                            if (editCount > 0) ...[
                              const SizedBox(width: 5),
                              _MiniBadge('$editCount edits', Colors.orange),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          branch,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          submitted ? 'Order Submitted' : 'Waiting Submission',
                          style: TextStyle(
                            fontSize: 12,
                            color: submitted
                                ? Colors.green.shade700
                                : Colors.grey,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 14,
                              color: Colors.blueGrey.shade500,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Open branch overview',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blueGrey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
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

class _AdditionalPanel extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final VoidCallback onViewAll;
  const _AdditionalPanel({required this.rows, required this.onViewAll});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.backgroundWidget,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Zone Additional Requests',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryColor,
                  ),
                ),
              ),
              FilledButton(
                onPressed: onViewAll,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                ),
                child: const Text('View All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text(
                    'No additional requests for this zone.',
                    style: TextStyle(color: AppColors.subText),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (_, index) =>
                      _AdditionalRequestCard(row: rows[index]),
                ),
        ),
      ],
    ),
  );
}

class _AdditionalRequestCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _AdditionalRequestCard({required this.row});
  @override
  Widget build(BuildContext context) {
    final status = _text(row['status']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_text(row['item_code'])} - ${_text(row['item_name'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              _StatusChip(status),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Text(
                  _text(row['branch_name']),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Text('Req: ', style: TextStyle(color: AppColors.subText)),
              Text(
                _numberText(row['request_qty']),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xffEAF6FC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _InfoCell('Branch Stock', row['branch_stock']),
                _InfoCell('Store Stock', row['store_stock']),
                _InfoCell('Sales', row['sales_45d']),
                _InfoCell('Final Reorder', row['final_reorder_qty']),
                _InfoCell('Inventory', row['inventory_qty']),
                _InfoCell('Fulfilled', row['fulfilled_qty']),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockCheckProjectSummary {
  final String batchId;
  final List<StockCheckTask> rows;

  const _StockCheckProjectSummary({required this.batchId, required this.rows});

  String get title => rows.isEmpty ? 'Untitled Stock Check' : rows.first.title;
  Set<String> get branches => rows.map((row) => row.branchName).toSet();
  int get submitted => rows.where((row) => row.isSubmitted).length;
  int get pending => rows.length - submitted;
  int get variances =>
      rows.where((row) => (row.variance ?? 0).abs() > .01).length;
  double get completion => rows.isEmpty ? 0 : submitted / rows.length;
  DateTime get sentAt => rows
      .map((row) => row.sentAt ?? DateTime(1970))
      .fold(
        DateTime(1970),
        (latest, date) => date.isAfter(latest) ? date : latest,
      );
}

class _StockCheckProjectCard extends StatelessWidget {
  final _StockCheckProjectSummary project;
  final VoidCallback onOpen, onDownload;

  const _StockCheckProjectCard({
    required this.project,
    required this.onOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final complete = project.pending == 0 && project.rows.isNotEmpty;
    final statusColor = complete
        ? const Color(0xff16A34A)
        : const Color(0xffF59E0B);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0F2942).withValues(alpha: .055),
            blurRadius: 18,
            offset: const Offset(0, 7),
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
                  color: const Color(0xff0EA5E9).withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder_copy_outlined,
                  color: Color(0xff0284C7),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  complete ? 'Completed' : 'In Progress',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            project.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${project.branches.length} branch${project.branches.length == 1 ? '' : 'es'} • ${project.rows.length} items • ${DateFormat('dd MMM yyyy').format(project.sentAt.toLocal())}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.subText, fontSize: 10.5),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              _ProjectMiniMetric(
                'Submitted',
                project.submitted,
                const Color(0xff16A34A),
              ),
              _ProjectMiniMetric(
                'Pending',
                project.pending,
                const Color(0xffF59E0B),
              ),
              _ProjectMiniMetric(
                'Variance',
                project.variances,
                const Color(0xffEF4444),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: project.completion,
              minHeight: 6,
              backgroundColor: const Color(0xffE2E8F0),
              color: statusColor,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Open Project'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: onDownload,
                tooltip: 'Download project',
                icon: const Icon(Icons.download_rounded, size: 19),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectMiniMetric extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _ProjectMiniMetric(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: color,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.subText, fontSize: 9),
        ),
      ],
    ),
  );
}

class _ReportPage extends StatelessWidget {
  final String title, subtitle;
  final Color accent;
  final List<Map<String, dynamic>> rows;
  final List<_ColumnDef> columns;
  final VoidCallback onExport;
  final Widget? footer;
  final List<_ReportKpi> kpis;
  final List<Widget> extraActions;
  final String exportLabel;
  const _ReportPage({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.rows,
    required this.columns,
    required this.onExport,
    this.footer,
    this.kpis = const [],
    this.extraActions = const [],
    this.exportLabel = 'Export Excel',
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
        const SizedBox(height: 12),
        Expanded(
          child: _DataTableCard(rows: rows, columns: columns, accent: accent),
        ),
        if (footer != null) ...[const SizedBox(height: 10), footer!],
      ],
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

class _ReportKpiCard extends StatelessWidget {
  final _ReportKpi kpi;
  const _ReportKpiCard({required this.kpi});

  @override
  Widget build(BuildContext context) => Container(
    height: 86,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border.withValues(alpha: .9)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xff0F2942).withValues(alpha: .045),
          blurRadius: 14,
          offset: const Offset(0, 5),
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
                  fontSize: 10.5,
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
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                kpi.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.subText, fontSize: 9.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HeroMetric {
  final String label, value;
  const _HeroMetric(this.label, this.value);
}

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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.white, accent.withValues(alpha: .075)],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: .18)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xff0F2942).withValues(alpha: .06),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .28),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.secondaryColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.subText, fontSize: 12),
              ),
            ],
          ),
        ),
        for (final metric in metrics) ...[
          Container(
            constraints: const BoxConstraints(minWidth: 92),
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: accent.withValues(alpha: .12)),
            ),
            child: Column(
              children: [
                Text(
                  metric.value,
                  style: const TextStyle(
                    color: AppColors.secondaryColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  metric.label,
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(width: 12),
        ...actions.map(
          (action) =>
              Padding(padding: const EdgeInsets.only(left: 8), child: action),
        ),
      ],
    ),
  );
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

class _DataTableCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final List<_ColumnDef> columns;
  final Color accent;
  const _DataTableCard({
    required this.rows,
    required this.columns,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _EmptyState(color: accent);
    final source = _ZoneGridSource(
      rows: rows,
      columns: columns,
      accent: accent,
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
            headerColor: accent.withValues(alpha: .09),
            gridLineColor: AppColors.border.withValues(alpha: .72),
            selectionColor: accent.withValues(alpha: .10),
            filterIconColor: accent,
            sortIconColor: accent,
          ),
          child: SfDataGrid(
            source: source,
            allowSorting: true,
            allowMultiColumnSorting: true,
            allowFiltering: true,
            allowColumnsResizing: true,
            columnWidthMode: ColumnWidthMode.none,
            gridLinesVisibility: GridLinesVisibility.horizontal,
            headerGridLinesVisibility: GridLinesVisibility.none,
            frozenColumnsCount: 1,
            rowHeight: 58,
            headerRowHeight: 62,
            columns: columns
                .map(
                  (column) => GridColumn(
                    columnName: column.key,
                    width: _columnWidth(column.key) + 34,
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
                          fontSize: 11,
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
            alignment: Alignment.centerLeft,
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
              fontSize: 12,
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

  List<String> get _dates {
    final values =
        widget.rows
            .map((row) => _text(row['run_date']))
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return values;
  }

  String? get _selectedDate {
    final dates = _dates;
    if (dates.isEmpty) return null;
    return _date != null && dates.contains(_date) ? _date : dates.first;
  }

  List<Map<String, dynamic>> get _selection {
    final date = _selectedDate;
    if (date == null) return const [];
    return widget.rows.where((row) {
      final dateMatches = _text(row['run_date']) == date;
      final branchMatches =
          _branch == 'ALL' || _text(row['branch_name']) == _branch;
      return dateMatches &&
          branchMatches &&
          _text(row['storage_path']).isNotEmpty;
    }).toList()..sort(
      (a, b) => _text(a['branch_name']).compareTo(_text(b['branch_name'])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final dates = _dates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportHeading(title: widget.title, subtitle: widget.subtitle),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.folder_zip_rounded,
                  color: widget.accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_selectedDate),
                  initialValue: _selectedDate,
                  decoration: _inputDecoration(
                    'Order date',
                    Icons.calendar_today_rounded,
                  ),
                  items: dates
                      .map(
                        (date) => DropdownMenuItem(
                          value: date,
                          child: Text(_displayDate(date)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _date = value),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_branch),
                  initialValue: _branch,
                  isExpanded: true,
                  decoration: _inputDecoration('Branch', Icons.store_rounded),
                  items: ['ALL', ...widget.zoneBranches]
                      .map(
                        (branch) => DropdownMenuItem(
                          value: branch,
                          child: Text(
                            branch == 'ALL' ? 'All Zone Branches' : branch,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _branch = value);
                  },
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${selection.length} file(s) ready',
                    style: const TextStyle(
                      color: AppColors.subText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 7),
                  FilledButton.icon(
                    onPressed: selection.isEmpty
                        ? null
                        : () => widget.onDownloadSelection(selection),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    icon: Icon(
                      selection.length > 1
                          ? Icons.folder_zip_rounded
                          : Icons.download_rounded,
                    ),
                    label: Text(
                      selection.length > 1
                          ? 'Download Zone ZIP'
                          : 'Download Excel',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: selection.isEmpty
              ? _EmptyState(color: widget.accent)
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: selection.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final row = selection[index];
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.table_view_rounded,
                            color: widget.accent,
                          ),
                        ),
                        title: Text(
                          _text(row['branch_name']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Order date: ${_displayDate(_text(row['run_date']))}',
                        ),
                        trailing: OutlinedButton.icon(
                          onPressed: () => widget.onDownloadOne(row),
                          icon: const Icon(Icons.download_rounded, size: 17),
                          label: const Text('Download'),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _BranchQuickView extends StatelessWidget {
  final String branch, runDate;
  final bool submitted;
  final int additionalCount, editCount;
  final VoidCallback onOpenDaily, onOpenAdditional, onOpenHistory;

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

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: SizedBox(
      width: 650,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 18),
            decoration: const BoxDecoration(
              color: Color(0xffEAF6FC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.store_rounded,
                  color: AppColors.primaryColor,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branch,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondaryColor,
                        ),
                      ),
                      Text(
                        'Branch overview • ${_displayDate(runDate)}',
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
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: submitted
                        ? Colors.green.withValues(alpha: .1)
                        : Colors.orange.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        submitted
                            ? Icons.check_circle_rounded
                            : Icons.schedule_rounded,
                        color: submitted ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        submitted ? 'Order Submitted' : 'Waiting Submission',
                        style: TextStyle(
                          color: submitted ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _DetailMetric(
                      'Additional Requests',
                      additionalCount,
                      Colors.orange,
                    ),
                    _DetailMetric('Order Edits', editCount, Colors.blue),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onOpenDaily,
                        icon: const Icon(Icons.shopping_cart_rounded),
                        label: const Text('Open Daily Order'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: onOpenAdditional,
                        icon: const Icon(Icons.add_box_rounded),
                        label: const Text('Open Additional'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onOpenHistory,
                        icon: const Icon(Icons.history_rounded),
                        label: const Text('Order History'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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

class _CountBadge extends StatelessWidget {
  final int count;
  final bool selected;
  const _CountBadge({required this.count, required this.selected});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: selected ? Colors.white.withValues(alpha: .25) : Colors.red,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      count > 999 ? '999+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

class _MiniBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniBadge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 10),
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

class _InfoCell extends StatelessWidget {
  final String label;
  final dynamic value;
  const _InfoCell(this.label, this.value);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9, color: AppColors.subText),
        ),
        const SizedBox(height: 3),
        Text(
          _numberText(value),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
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

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _prettyStatus(status),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
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

class _PageDef {
  final IconData icon;
  final String label;
  const _PageDef(this.icon, this.label);
}

class _ColumnDef {
  final String key, label;
  const _ColumnDef(this.key, this.label);
}

class _Stat {
  final IconData icon;
  final String title, value;
  final Color color;
  final String? subtitle;
  const _Stat(this.icon, this.title, this.value, this.color, {this.subtitle});
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
      status.contains('approved')) {
    return Colors.green;
  }
  if (status.contains('sent')) return Colors.blue;
  return Colors.orange;
}

double _columnWidth(String key) {
  if (key.contains('name') || key == 'reason' || key == 'note') return 240;
  if (key.contains('branch')) return 150;
  if (key.contains('date') || key.contains('created')) return 145;
  return 115;
}

String _safe(String value) =>
    value.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').replaceAll(' ', '_');
