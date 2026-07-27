// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, unused_element

import 'dart:async';
import 'dart:html' as html;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

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
  Timer? _searchDebounce;

  bool _loading = true;
  bool _drawerCollapsed = false;
  bool _busy = false;
  bool _reportLoading = false;
  String? _error;
  int _page = 0;
  String _selectedBranch = 'ALL';
  String _query = '';

  List<Map<String, dynamic>> _branches = const [];
  List<Map<String, dynamic>> _dailyPageRows = const [];
  int _dailyTotal = 0;
  int _dailyPageIndex = 0;
  bool _dailyLoading = false;
  String? _dailyError;
  String _dailyRequestKey = '';
  int _dailyRequestId = 0;
  List<Map<String, dynamic>> _additional = const [];
  List<Map<String, dynamic>> _mismatch = const [];
  List<Map<String, dynamic>> _maxAdj = const [];
  List<Map<String, dynamic>> _dailyExports = const [];
  List<Map<String, dynamic>> _nonReceivedExports = const [];
  List<Map<String, dynamic>> _edits = const [];
  Map<String, Map<String, dynamic>> _submissions = const {};

  static const _pages = [
    _PageDef(Icons.dashboard_rounded, 'Dashboard'),
    _PageDef(Icons.warning_amber_rounded, 'Mismatch Report'),
    _PageDef(Icons.trending_up_rounded, 'Max Adjustment'),
    _PageDef(Icons.shopping_cart_rounded, 'Daily Order'),
    _PageDef(Icons.send_to_mobile_rounded, 'Additional Orders'),
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
    _searchDebounce?.cancel();
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
      if (_page == 3) await _loadDailyPage(reset: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  static const int _dailyPageSize = 100;
  static const String _dailyColumns =
      'run_date,branch,item_code,item_name,branch_stock,mismatch_stock,'
      'store_stock,pending_stock_received,reorder_qty_num,'
      'final_reorder_qty_store_stock_gt_0,category,barcode';

  Future<void> _loadDailyPage({bool reset = false}) async {
    final requestId = ++_dailyRequestId;
    final branches = _branches
        .map((row) => _text(row['branch_name']))
        .where((name) => name.isNotEmpty)
        .toList();
    if (branches.isEmpty) {
      if (mounted) setState(() => _dailyPageRows = const []);
      return;
    }
    final page = reset ? 0 : _dailyPageIndex;
    final requestKey = '$_selectedBranch|${_query.trim()}|$page';
    setState(() {
      _dailyLoading = true;
      _dailyError = null;
      if (reset) _dailyPageIndex = 0;
    });
    try {
      dynamic query = _client
          .from('daily_order')
          .select(_dailyColumns)
          .eq('run_date', widget.runDate);
      query = _selectedBranch == 'ALL'
          ? query.inFilter('branch', branches)
          : query.eq('branch', _selectedBranch);
      final needle = _query
          .trim()
          .replaceAll(',', ' ')
          .replaceAll('(', ' ')
          .replaceAll(')', ' ');
      if (needle.isNotEmpty) {
        query = query.or(
          'item_code.ilike.%$needle%,item_name.ilike.%$needle%,'
          'barcode.ilike.%$needle%',
        );
      }
      final from = page * _dailyPageSize;
      final response = await query
          .order('branch', ascending: true)
          .order('item_code', ascending: true)
          .range(from, from + _dailyPageSize - 1)
          .count(CountOption.exact);
      if (!mounted || requestId != _dailyRequestId) return;
      setState(() {
        _dailyPageRows = List<Map<String, dynamic>>.from(response.data);
        _dailyTotal = response.count;
        _dailyPageIndex = page;
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
    setState(() => _page = page);
    if (page == 3) {
      final key = '$_selectedBranch|${_query.trim()}|0';
      if (_dailyRequestKey != key || _dailyPageRows.isEmpty) {
        await _loadDailyPage(reset: true);
      }
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
    setState(() => _selectedBranch = value);
    if (_page == 3) _loadDailyPage(reset: true);
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    if (_page != 3) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _loadDailyPage(reset: true),
    );
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
            _page = 6;
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
              3 => _dailyPage(),
              4 => _additionalPage(),
              5 => _nonReceivedPage(),
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
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 600,
                child: _BranchGrid(
                  branches: _branches,
                  submissions: _submissions,
                  edits: _edits,
                  additional: _additional,
                  selectedBranch: _selectedBranch,
                  onOpen: _openBranch,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _AdditionalPanel(
                  rows: _filtered(_additional, 'branch_name'),
                  onViewAll: () => _changePage(4),
                ),
              ),
            ],
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
      onExport: () => _exportExcel('Max_Adjustment', rows, columns),
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
      onExport: () => _exportExcel('Additional_Orders', rows, columns),
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

  const _ZoneHeader({
    required this.title,
    required this.zoneName,
    required this.runDate,
    required this.branches,
    required this.selectedBranch,
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
              items: ['ALL', ...branches]
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

class _ReportPage extends StatelessWidget {
  final String title, subtitle;
  final Color accent;
  final List<Map<String, dynamic>> rows;
  final List<_ColumnDef> columns;
  final VoidCallback onExport;
  final Widget? footer;
  const _ReportPage({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.rows,
    required this.columns,
    required this.onExport,
    this.footer,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: _ReportHeading(title: title, subtitle: subtitle),
          ),
          FilledButton.icon(
            onPressed: onExport,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Export Excel'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Expanded(
        child: _DataTableCard(rows: rows, columns: columns, accent: accent),
      ),
      if (footer != null) ...[const SizedBox(height: 10), footer!],
    ],
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
  final String message;
  final VoidCallback onRetry;
  const _DailyOrderError({required this.message, required this.onRetry});

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
          const Text(
            'Daily Order could not be loaded',
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
