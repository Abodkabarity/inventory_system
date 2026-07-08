import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/stock_check_excel_exporter.dart';
import '../../../domain/entities/stock_check_task.dart';
import '../../orders/widgets/branch_stock_check_page.dart';

const _storeStockCheckDestination = 'STORE';

class StockCheckPage extends StatefulWidget {
  final String runDate;
  final String source;
  final String sourceTitle;
  final int storeInboxPendingCount;
  final int storeInboxOverdueCount;
  final bool initialShowStoreInbox;

  const StockCheckPage({
    super.key,
    required this.runDate,
    this.source = 'inventory',
    this.sourceTitle = 'Stock Check',
    this.storeInboxPendingCount = 0,
    this.storeInboxOverdueCount = 0,
    this.initialShowStoreInbox = false,
  });

  @override
  State<StockCheckPage> createState() => _StockCheckPageState();
}

class _StockCheckPageState extends State<StockCheckPage> {
  final _client = Supabase.instance.client;
  final _titleController = TextEditingController();

  final _items = <_StockCheckItem>[];
  final _importRows = <_StockCheckDraftRow>[];
  final _selectedBranches = <String>{};
  bool _showStoreInbox = false;
  List<String> _branches = [];
  List<StockCheckTask> _sentRows = [];
  String? _selectedBatchId;
  late DateTime _sentFrom;
  late DateTime _sentTo;
  late DateTime _deadlineFrom;
  late DateTime _deadlineTo;
  bool _loading = true;
  bool _sending = false;
  String? _deletingBatchId;
  bool _includeBarcodeStickerCheck = false;
  String _message = '';
  String _error = '';

  bool get _canSendToStore => widget.source.trim().toLowerCase() == 'inventory';
  bool get _hasStoreInbox => widget.source.trim().toLowerCase() == 'store';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _sentFrom = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    _sentTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _deadlineFrom = DateTime(now.year, now.month, now.day);
    _deadlineTo = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    ).add(const Duration(days: 1));
    _showStoreInbox = _hasStoreInbox && widget.initialShowStoreInbox;
    _titleController.text = '${widget.sourceTitle} ${widget.runDate}';
    _load();
  }

  @override
  void didUpdateWidget(covariant StockCheckPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasStoreInbox &&
        widget.initialShowStoreInbox &&
        !oldWidget.initialShowStoreInbox) {
      _showStoreInbox = true;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final branchesRes = await _client
          .from('branches')
          .select('branch_name')
          .eq('is_active', true)
          .order('branch_name');

      var sentRows = <StockCheckTask>[];
      String tableError = '';
      try {
        final rows = await _client
            .from('stock_check_tasks')
            .select()
            .eq('source', widget.source)
            .order('sent_at', ascending: false);
        sentRows = List<Map<String, dynamic>>.from(
          rows,
        ).map(StockCheckTask.fromMap).toList();
      } catch (e) {
        tableError =
            'Stock check table is not ready. Run supabase/sql/stock_check_tasks.sql first.';
      }

      if (!mounted) return;
      setState(() {
        final destinations = List<Map<String, dynamic>>.from(branchesRes)
            .map((e) => (e['branch_name'] ?? '').toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        if (_canSendToStore &&
            !destinations.contains(_storeStockCheckDestination)) {
          destinations.add(_storeStockCheckDestination);
        }
        destinations.sort((a, b) {
          if (a == _storeStockCheckDestination) return -1;
          if (b == _storeStockCheckDestination) return 1;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
        _branches = destinations;
        _sentRows = sentRows;
        if (_selectedBatchId == null ||
            !sentRows.any((row) => row.batchId == _selectedBatchId)) {
          _selectedBatchId = sentRows.isEmpty ? null : sentRows.first.batchId;
        }
        _error = tableError;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _importProductsFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null) return;
    if (bytes == null) {
      setState(() {
        _error = 'Could not read the selected import file.';
        _message = '';
      });
      return;
    }

    try {
      final importData = _readStockCheckProductsImport(
        bytes,
        file.extension?.toLowerCase() ?? '',
      );
      final importedRows = importData.rows;
      final importedProducts = importData.products;
      if (importedRows.isNotEmpty) _addImportRows(importedRows);
      if (importedProducts.isNotEmpty) _addProducts(importedProducts);
      setState(() {
        _message = 'Imported ${importedProducts.length} item(s).';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  static String _headerKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  void _addImportRows(List<_StockCheckDraftRow> rows) {
    final existing = _importRows
        .map(
          (e) => '${e.branchName.toLowerCase()}::${e.itemCode.toLowerCase()}',
        )
        .toSet();
    for (final row in rows) {
      final key =
          '${row.branchName.toLowerCase()}::${row.itemCode.toLowerCase()}';
      if (existing.add(key)) {
        _importRows.add(row);
      }
    }
    setState(() {});
  }

  void _addProducts(List<_StockCheckItem> items) {
    final existing = _items.map((e) => e.itemCode.toLowerCase()).toSet();
    for (final item in items) {
      if (existing.add(item.itemCode.toLowerCase())) {
        _items.add(item);
      }
    }
    setState(() {});
  }

  List<_StockCheckDraftRow> _buildDraftRows() {
    final rows = <_StockCheckDraftRow>[..._importRows];
    for (final branch in _selectedBranches) {
      for (final item in _items) {
        rows.add(
          _StockCheckDraftRow(
            branchName: branch,
            itemCode: item.itemCode,
            itemName: item.itemName,
          ),
        );
      }
    }

    final seen = <String>{};
    return rows.where((row) {
      final key =
          '${row.branchName.toLowerCase()}::${row.itemCode.toLowerCase()}';
      return seen.add(key);
    }).toList();
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final draftRows = _buildDraftRows();
    if (title.isEmpty || draftRows.isEmpty) {
      setState(() {
        _error =
            'Add a title, choose destinations, and choose/import products. CSV requires item_code,item_name; branch is optional.';
      });
      return;
    }
    if (!_deadlineTo.isAfter(DateTime.now())) {
      setState(() {
        _error = 'Choose a completion window that ends in the future.';
      });
      return;
    }

    setState(() {
      _sending = true;
      _error = '';
      _message = '';
    });
    try {
      final batchId = const Uuid().v4();
      final now = DateTime.now().toIso8601String();
      final expiresAt = _deadlineTo.toIso8601String();
      final sentBranchCount = draftRows.map((e) => e.branchName).toSet().length;
      final payload = <Map<String, dynamic>>[];
      for (final row in draftRows) {
        payload.add({
          'batch_id': batchId,
          'title': title,
          'source': widget.source,
          'run_date': widget.runDate,
          'branch_name': row.branchName,
          'item_code': row.itemCode,
          'item_name': row.itemName,
          'system_qty': null,
          'include_barcode_sticker_check': _includeBarcodeStickerCheck,
          'barcode_sticker_is_correct': null,
          'status': 'pending',
          'sent_at': now,
          'expires_at': expiresAt,
          'updated_at': now,
        });
      }
      await _client.from('stock_check_tasks').insert(payload);
      _items.clear();
      _importRows.clear();
      await _load();
      if (!mounted) return;
      setState(() {
        _message = 'Stock check sent to $sentBranchCount branch(es).';
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _sending = false;
      });
    }
  }

  Future<void> _deleteBatch(_StockCheckBatch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => _DeleteStockCheckDialog(batch: batch),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deletingBatchId = batch.id;
      _error = '';
      _message = '';
    });

    try {
      await _client.from('stock_check_tasks').delete().eq('batch_id', batch.id);
      if (!mounted) return;
      setState(() {
        _sentRows.removeWhere((row) => row.batchId == batch.id);
        if (_selectedBatchId == batch.id) {
          final batches = _batches();
          _selectedBatchId = batches.isEmpty ? null : batches.first.id;
        }
        _message = 'Stock check "${batch.title}" deleted.';
        _deletingBatchId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _deletingBatchId = null;
      });
    }
  }

  Future<void> _editBatchDeadline(_StockCheckBatch batch) async {
    final now = DateTime.now();
    final initialStart = batch.sentAt ?? now;
    final initialEnd =
        batch.expiresAt ??
        DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).add(const Duration(days: 1));
    final result = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => StockCheckDateRangePickerDialog(
        initialRange: DateTimeRange(start: initialStart, end: initialEnd),
        mode: StockCheckDateRangePickerMode.deadline,
      ),
    );
    if (result == null || !mounted) return;
    final expiresAt = DateTime(
      result.end.year,
      result.end.month,
      result.end.day,
      23,
      59,
      59,
    );
    if (!expiresAt.isAfter(DateTime.now())) {
      setState(() {
        _error = 'Choose a new deadline that ends in the future.';
        _message = '';
      });
      return;
    }
    try {
      await _client
          .from('stock_check_tasks')
          .update({
            'expires_at': expiresAt.toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('batch_id', batch.id);
      await _load();
      if (!mounted) return;
      setState(() {
        _message =
            'Deadline updated for "${batch.title}" to ${_fmtDate(expiresAt)}.';
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _message = '';
      });
    }
  }

  List<_StockCheckBatch> _batches() {
    final byBatch = <String, List<StockCheckTask>>{};
    for (final row in _filteredSentRows()) {
      byBatch.putIfAbsent(row.batchId, () => []).add(row);
    }
    final batches = byBatch.entries
        .map((entry) => _StockCheckBatch(id: entry.key, rows: entry.value))
        .toList();
    batches.sort((a, b) {
      final aDate = a.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return batches;
  }

  List<StockCheckTask> _filteredSentRows() {
    return _sentRows.where((row) {
      final sentAt = row.sentAt;
      if (sentAt == null) return false;
      return !sentAt.isBefore(_sentFrom) && !sentAt.isAfter(_sentTo);
    }).toList();
  }

  List<StockCheckTask> _selectedBatchRows(List<_StockCheckBatch> batches) {
    if (batches.isEmpty) return const [];
    final selected = batches.where((e) => e.id == _selectedBatchId);
    return selected.isEmpty ? batches.first.rows : selected.first.rows;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _sentRows.where((e) => e.isPending).length;
    final submitted = _sentRows.where((e) => e.isSubmitted).length;
    final batches = _batches();
    final selectedRows = _selectedBatchRows(batches);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryColor),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final header = _Header(
                    title: widget.sourceTitle,
                    pending: pending,
                    submitted: submitted,
                    total: _sentRows.length,
                    onRefresh: _load,
                    onExport: selectedRows.isEmpty
                        ? null
                        : () => StockCheckExcelExporter.export(
                            rows: selectedRows,
                            title: selectedRows.first.title,
                          ),
                  );

                  if (_showStoreInbox && _hasStoreInbox) {
                    return Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          header,
                          const SizedBox(height: 16),
                          _StoreStockCheckTabs(
                            showInbox: _showStoreInbox,
                            pendingCount: widget.storeInboxPendingCount,
                            overdueCount: widget.storeInboxOverdueCount,
                            onChanged: (value) {
                              setState(() => _showStoreInbox = value);
                            },
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: BranchStockCheckPage(
                              branchName: _storeStockCheckDestination,
                              embedded: true,
                              onBack: () =>
                                  setState(() => _showStoreInbox = false),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final workspaceHeight = math.max(
                    680.0,
                    constraints.maxHeight * .76,
                  );
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        header,
                        const SizedBox(height: 16),
                        if (_hasStoreInbox) ...[
                          _StoreStockCheckTabs(
                            showInbox: _showStoreInbox,
                            pendingCount: widget.storeInboxPendingCount,
                            overdueCount: widget.storeInboxOverdueCount,
                            onChanged: (value) {
                              setState(() => _showStoreInbox = value);
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildComposer(),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: workspaceHeight,
                          child: _buildWorkspace(batches, selectedRows),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildComposer() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _PanelTitle(
                  icon: Icons.fact_check_rounded,
                  title: 'Create Stock Check',
                ),
              ),
              SizedBox(
                width: 206,
                child: _BarcodeStickerOption(
                  value: _includeBarcodeStickerCheck,
                  onChanged: (value) {
                    setState(() => _includeBarcodeStickerCheck = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _importProductsFile,
                icon: const Icon(
                  Icons.upload_file_rounded,
                  color: AppColors.secondaryColor,
                ),
                label: const Text(
                  'Import Items',
                  style: TextStyle(
                    color: AppColors.secondaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                ),
                label: const Text('Send Stock Check'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _titleController,
                  decoration: _decoration('Stock check title'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BranchPickerField(
                  selectedCount: _selectedBranches.length,
                  totalCount: _branches.length,
                  preview: _branchPreviewText(),
                  onTap: _branches.isEmpty ? () {} : _openBranchPicker,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProductPickerField(
                  productCount: _items.length,
                  importCount: _importRows.length,
                  preview: _productPreviewText(),
                  onTap: _openProductPicker,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DeadlinePickerField(
                  label:
                      '${_fmtDate(_deadlineFrom)}  to  ${_fmtDate(_deadlineTo)}',
                  onTap: _pickDeadlineRange,
                ),
              ),
            ],
          ),
          if (_importRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ImportPreview(
              rows: _importRows,
              onClear: () => setState(() => _importRows.clear()),
            ),
          ],
          if (_message.isNotEmpty || _error.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (_message.isNotEmpty) _Banner(message: _message, ok: true),
            if (_error.isNotEmpty) _Banner(message: _error, ok: false),
          ],
          const SizedBox(height: 8),
          const Text(
            'Import columns: item_code, item_name. Optional column: branch. Supported: CSV, XLSX.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace(
    List<_StockCheckBatch> batches,
    List<StockCheckTask> selectedRows,
  ) {
    if (batches.isEmpty) {
      return const _EmptyState();
    }
    final effectiveSelectedBatchId = selectedRows.isEmpty
        ? _selectedBatchId
        : selectedRows.first.batchId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 330,
          child: _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PanelTitle(
                  icon: Icons.view_agenda_rounded,
                  title: 'Sent Stock Checks',
                ),
                const SizedBox(height: 10),
                _DateRangeFilterButton(
                  label: '${_fmtDate(_sentFrom)}  to  ${_fmtDate(_sentTo)}',
                  onPressed: _pickSentDateRange,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: batches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final batch = batches[index];
                      return _StockCheckBatchCard(
                        batch: batch,
                        selected: batch.id == effectiveSelectedBatchId,
                        deleting: _deletingBatchId == batch.id,
                        onTap: () =>
                            setState(() => _selectedBatchId = batch.id),
                        onEditDeadline: () => _editBatchDeadline(batch),
                        onDelete: () => _deleteBatch(batch),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _StockCheckResultTable(rows: selectedRows)),
      ],
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.backgroundWidget,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryColor),
      ),
    );
  }

  String _branchPreviewText() {
    if (_branches.isEmpty) return 'No destinations loaded';
    if (_selectedBranches.isEmpty) return '';
    if (_selectedBranches.length == _branches.length) return 'All destinations';
    return _selectedBranches.take(3).join(', ') +
        (_selectedBranches.length > 3
            ? ' +${_selectedBranches.length - 3} more'
            : '');
  }

  String _productPreviewText() {
    if (_items.isEmpty && _importRows.isEmpty) return 'Choose Items';
    final parts = <String>[];
    if (_items.isNotEmpty) parts.add('${_items.length} item(s)');
    if (_importRows.isNotEmpty) {
      parts.add('${_importRows.length} imported item(s)');
    }
    return parts.join(' + ');
  }

  Future<void> _openBranchPicker() async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _BranchPickerDialog(
        branches: _branches,
        selectedBranches: _selectedBranches,
      ),
    );

    if (selected == null || !mounted) return;
    setState(() {
      _selectedBranches
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _openProductPicker() async {
    final selected = await showDialog<List<_StockCheckItem>>(
      context: context,
      builder: (_) => _ProductPickerDialog(initiallySelected: _items),
    );

    if (selected == null || !mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _pickSentDateRange() async {
    final result = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => StockCheckDateRangePickerDialog(
        initialRange: DateTimeRange(start: _sentFrom, end: _sentTo),
        mode: StockCheckDateRangePickerMode.history,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _sentFrom = DateTime(
        result.start.year,
        result.start.month,
        result.start.day,
      );
      _sentTo = DateTime(
        result.end.year,
        result.end.month,
        result.end.day,
        23,
        59,
        59,
      );
      final batches = _batches();
      _selectedBatchId = batches.isEmpty ? null : batches.first.id;
    });
  }

  Future<void> _pickDeadlineRange() async {
    final result = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => StockCheckDateRangePickerDialog(
        initialRange: DateTimeRange(start: _deadlineFrom, end: _deadlineTo),
        mode: StockCheckDateRangePickerMode.deadline,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _deadlineFrom = DateTime(
        result.start.year,
        result.start.month,
        result.start.day,
      );
      _deadlineTo = DateTime(
        result.end.year,
        result.end.month,
        result.end.day,
        23,
        59,
        59,
      );
    });
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _StockCheckResultTable extends StatefulWidget {
  final List<StockCheckTask> rows;

  const _StockCheckResultTable({required this.rows});

  @override
  State<_StockCheckResultTable> createState() => _StockCheckResultTableState();
}

class _StockCheckResultTableState extends State<_StockCheckResultTable> {
  final _searchController = TextEditingController();
  String _search = '';
  String _branchFilter = 'ALL';
  List<String> _branches = const [];
  List<StockCheckTask> _filteredRows = const [];
  bool _showBarcodeSticker = false;

  @override
  void initState() {
    super.initState();
    _rebuildIndexes();
  }

  @override
  void didUpdateWidget(covariant _StockCheckResultTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_batchId(oldWidget.rows) != _batchId(widget.rows)) {
      _searchController.clear();
      _search = '';
      _branchFilter = 'ALL';
    }
    _rebuildIndexes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.table_chart_rounded,
            title: widget.rows.isEmpty
                ? 'Stock Check Details'
                : widget.rows.first.title,
          ),
          if (widget.rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ResultDeadlineStrip(expiresAt: widget.rows.first.expiresAt),
          ],
          const SizedBox(height: 12),
          if (widget.rows.isNotEmpty) ...[
            Row(
              children: [
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    initialValue: _branchFilter,
                    decoration: _filterDecoration('Branch'),
                    items: [
                      const DropdownMenuItem(
                        value: 'ALL',
                        child: Text('All branches'),
                      ),
                      ..._branches.map(
                        (branch) => DropdownMenuItem(
                          value: branch,
                          child: Text(branch, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _branchFilter = value ?? 'ALL';
                        _rebuildIndexes();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: _filterDecoration(
                      'Search branch, item code, or item name',
                      icon: Icons.search_rounded,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _search = value;
                        _rebuildIndexes();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    '${_filteredRows.length} row(s)',
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: widget.rows.isEmpty
                ? const Center(
                    child: Text(
                      'Select a stock check card to view its table.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _FastStockCheckResultsTable(
                      rows: _filteredRows,
                      showBarcodeSticker: _showBarcodeSticker,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _batchId(List<StockCheckTask> rows) {
    return rows.isEmpty ? '' : rows.first.batchId;
  }

  void _rebuildIndexes() {
    final branches =
        widget.rows
            .map((row) => row.branchName.trim())
            .where((branch) => branch.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (_branchFilter != 'ALL' && !branches.contains(_branchFilter)) {
      _branchFilter = 'ALL';
    }

    final needle = _search.trim().toLowerCase();
    final filtered =
        widget.rows.where((row) {
          final branchOk =
              _branchFilter == 'ALL' || row.branchName.trim() == _branchFilter;
          final searchOk =
              needle.isEmpty ||
              row.branchName.toLowerCase().contains(needle) ||
              row.itemCode.toLowerCase().contains(needle) ||
              row.itemName.toLowerCase().contains(needle);
          return branchOk && searchOk;
        }).toList()..sort((a, b) {
          final branch = a.branchName.toLowerCase().compareTo(
            b.branchName.toLowerCase(),
          );
          if (branch != 0) return branch;
          final name = a.itemName.toLowerCase().compareTo(
            b.itemName.toLowerCase(),
          );
          if (name != 0) return name;
          return a.itemCode.toLowerCase().compareTo(b.itemCode.toLowerCase());
        });

    _branches = branches;
    _filteredRows = filtered;
    _showBarcodeSticker = widget.rows.any(
      (row) => row.includeBarcodeStickerCheck,
    );
  }

  static InputDecoration _filterDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD9E8F5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4),
      ),
    );
  }

  static String _yesNo(bool? value) {
    if (value == null) return '';
    return value ? 'Yes' : 'No';
  }
}

class _StockCheckItem {
  final String itemCode;
  final String itemName;

  const _StockCheckItem({required this.itemCode, required this.itemName});
}

class _StockCheckProductsImport {
  final List<_StockCheckItem> products;
  final List<_StockCheckDraftRow> rows;

  const _StockCheckProductsImport({required this.products, required this.rows});
}

_StockCheckProductsImport _readStockCheckProductsImport(
  Uint8List bytes,
  String extension,
) {
  final table = extension == 'csv'
      ? _readStockCheckProductsCsv(bytes)
      : _readStockCheckProductsXlsx(bytes);
  return _stockCheckProductsFromTable(table);
}

List<List<dynamic>> _readStockCheckProductsCsv(Uint8List bytes) {
  String text;
  try {
    text = utf8.decode(bytes);
  } catch (_) {
    text = latin1.decode(bytes);
  }
  return const CsvToListConverter().convert(text);
}

List<List<dynamic>> _readStockCheckProductsXlsx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String fileText(String name) {
    final file = archive.findFile(name);
    if (file == null) return '';
    return utf8.decode(file.content);
  }

  final sharedStrings = <String>[];
  final sharedXml = fileText('xl/sharedStrings.xml');
  if (sharedXml.isNotEmpty) {
    final doc = XmlDocument.parse(sharedXml);
    for (final si in doc.findAllElements('si')) {
      sharedStrings.add(si.findAllElements('t').map((e) => e.innerText).join());
    }
  }

  var sheetPath = 'xl/worksheets/sheet1.xml';
  final workbookXml = fileText('xl/workbook.xml');
  final relsXml = fileText('xl/_rels/workbook.xml.rels');
  if (workbookXml.isNotEmpty && relsXml.isNotEmpty) {
    final workbook = XmlDocument.parse(workbookXml);
    final firstSheet = workbook.findAllElements('sheet').firstOrNull;
    final relId = firstSheet?.getAttribute('r:id');
    if (relId != null) {
      final rels = XmlDocument.parse(relsXml);
      final rel = rels
          .findAllElements('Relationship')
          .where((e) => e.getAttribute('Id') == relId)
          .firstOrNull;
      final target = rel?.getAttribute('Target');
      if (target != null && target.trim().isNotEmpty) {
        sheetPath = target.startsWith('worksheets/')
            ? 'xl/$target'
            : target.startsWith('/xl/')
            ? target.substring(1)
            : 'xl/$target';
      }
    }
  }

  final sheetXml = fileText(sheetPath);
  if (sheetXml.isEmpty) {
    throw Exception('Could not read the first worksheet from the XLSX file.');
  }
  final doc = XmlDocument.parse(sheetXml);
  final table = <List<dynamic>>[];
  for (final rowNode in doc.findAllElements('row')) {
    final cells = <int, String>{};
    var maxIndex = -1;
    for (final cell in rowNode.findElements('c')) {
      final index = _xlsxColumnIndex(cell.getAttribute('r') ?? '');
      if (index < 0) continue;
      maxIndex = index > maxIndex ? index : maxIndex;
      final type = cell.getAttribute('t');
      final valueNode = cell.findElements('v').firstOrNull;
      final inlineText = cell
          .findAllElements('t')
          .map((e) => e.innerText)
          .join();
      var value = valueNode?.innerText ?? inlineText;
      if (type == 's') {
        final sharedIndex = int.tryParse(value) ?? -1;
        value = sharedIndex >= 0 && sharedIndex < sharedStrings.length
            ? sharedStrings[sharedIndex]
            : '';
      }
      cells[index] = value;
    }
    if (maxIndex >= 0) {
      table.add(List.generate(maxIndex + 1, (index) => cells[index] ?? ''));
    }
  }
  return table;
}

int _xlsxColumnIndex(String cellRef) {
  final letters = RegExp(
    r'^[A-Z]+',
    caseSensitive: false,
  ).stringMatch(cellRef)?.toUpperCase();
  if (letters == null || letters.isEmpty) return -1;
  var value = 0;
  for (final unit in letters.codeUnits) {
    value = value * 26 + (unit - 64);
  }
  return value - 1;
}

_StockCheckProductsImport _stockCheckProductsFromTable(
  List<List<dynamic>> table,
) {
  if (table.isEmpty) {
    return const _StockCheckProductsImport(products: [], rows: []);
  }
  final headers = table.first
      .map((e) => _StockCheckPageState._headerKey(e.toString()))
      .toList();

  int findColumn(List<String> names) {
    for (final name in names.map(_StockCheckPageState._headerKey)) {
      final index = headers.indexOf(name);
      if (index >= 0) return index;
    }
    return -1;
  }

  final branchIndex = findColumn(['branch', 'branch_name', 'branch name']);
  final codeIndex = findColumn(['item_code', 'item code', 'itemcode']);
  final nameIndex = findColumn(['item_name', 'item name', 'itemname']);
  if (codeIndex < 0 || nameIndex < 0) {
    throw Exception(
      'Import file must include item_code and item_name. branch is optional.',
    );
  }

  final rows = <_StockCheckDraftRow>[];
  final products = <_StockCheckItem>[];
  for (final raw in table.skip(1)) {
    String cell(int index) =>
        index >= 0 && index < raw.length ? raw[index].toString().trim() : '';
    final branch = cell(branchIndex);
    final code = cell(codeIndex);
    final name = cell(nameIndex);
    if (code.isEmpty || name.isEmpty) continue;
    if (branchIndex >= 0 && branch.isNotEmpty) {
      rows.add(
        _StockCheckDraftRow(branchName: branch, itemCode: code, itemName: name),
      );
    } else {
      products.add(_StockCheckItem(itemCode: code, itemName: name));
    }
  }
  return _StockCheckProductsImport(products: products, rows: rows);
}

class _FastStockCheckResultsTable extends StatelessWidget {
  final List<StockCheckTask> rows;
  final bool showBarcodeSticker;

  const _FastStockCheckResultsTable({
    required this.rows,
    required this.showBarcodeSticker,
  });

  static const double _branchW = 130;
  static const double _codeW = 130;
  static const double _nameW = 520;
  static const double _qtyW = 95;
  static const double _diffW = 68;
  static const double _barcodeW = 220;
  static const double _statusW = 200;

  double get _width =>
      _branchW +
      _codeW +
      _nameW +
      (_qtyW * 2) +
      _diffW +
      (showBarcodeSticker ? _barcodeW : 0) +
      _statusW;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Column(
        children: [
          _row(
            cells: [
              _header('Branch', _branchW),
              _header('Item Code', _codeW),
              _header('Item Name', _nameW),
              _header('System', _qtyW),
              _header('Actual', _qtyW),
              _header('Diff', _diffW),
              if (showBarcodeSticker)
                _header('Barcode Sticker is Correct', _barcodeW),
              _header('Status', _statusW),
            ],
            background: const Color(0xFFEFF6FF),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD9E8F5)),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
              ),
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFFD9E8F5)),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return _row(
                    cells: [
                      _cell(row.branchName, _branchW),
                      _cell(row.itemCode, _codeW),
                      _cell(row.itemName, _nameW, maxLines: 2),
                      _cell(row.systemQty?.toString() ?? '', _qtyW),
                      _cell(row.actualQty?.toString() ?? '', _qtyW),
                      _cell(row.variance?.toString() ?? '', _diffW),
                      if (showBarcodeSticker)
                        _cell(
                          row.includeBarcodeStickerCheck
                              ? _StockCheckResultTableState._yesNo(
                                  row.barcodeStickerIsCorrect,
                                )
                              : '',
                          _barcodeW,
                        ),
                      _statusCell(row.isSubmitted),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row({required List<Widget> cells, Color? background}) {
    return SizedBox(
      width: _width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background ?? Colors.white,
          border: const Border(
            left: BorderSide(color: Color(0xFFD9E8F5)),
            right: BorderSide(color: Color(0xFFD9E8F5)),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: cells),
      ),
    );
  }

  Widget _header(String text, double width) {
    return Container(
      width: width,
      height: 48,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFD9E8F5))),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _cell(String text, double width, {int maxLines = 1}) {
    return Container(
      width: width,
      height: 54,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFD9E8F5))),
      ),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _statusCell(bool done) {
    return Container(
      width: _statusW,
      height: 54,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFD9E8F5))),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: _StatusChip(done: done),
      ),
    );
  }
}

class _ResultDeadlineStrip extends StatelessWidget {
  final DateTime? expiresAt;

  const _ResultDeadlineStrip({required this.expiresAt});

  @override
  Widget build(BuildContext context) {
    final expired =
        expiresAt != null && DateTime.now().isAfter(expiresAt!.toLocal());
    final color = expired ? const Color(0xFFDC2626) : const Color(0xFF0F766E);
    final bg = expired ? const Color(0xFFFFF1F2) : const Color(0xFFF0FDFA);
    final border = expired ? const Color(0xFFFCA5A5) : const Color(0xFF99F6E4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            expired ? Icons.lock_clock_rounded : Icons.timer_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _StockCheckBatchCard._deadlineText(expiresAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockCheckDraftRow {
  final String branchName;
  final String itemCode;
  final String itemName;

  const _StockCheckDraftRow({
    required this.branchName,
    required this.itemCode,
    required this.itemName,
  });
}

class _StockCheckBatch {
  final String id;
  final List<StockCheckTask> rows;

  const _StockCheckBatch({required this.id, required this.rows});

  String get title => rows.isEmpty ? 'Stock Check' : rows.first.title;
  DateTime? get sentAt => rows.isEmpty ? null : rows.first.sentAt;
  DateTime? get expiresAt => rows.isEmpty ? null : rows.first.expiresAt;
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!.toLocal());
  int get total => rows.length;
  int get pending => rows.where((row) => row.isPending).length;
  int get submitted => rows.where((row) => row.isSubmitted).length;
  int get branches => rows.map((row) => row.branchName).toSet().length;
  int get products => rows.map((row) => row.itemCode).toSet().length;
}

class _Header extends StatelessWidget {
  final String title;
  final int pending;
  final int submitted;
  final int total;
  final VoidCallback onRefresh;
  final VoidCallback? onExport;

  const _Header({
    required this.title,
    required this.pending,
    required this.submitted,
    required this.total,
    required this.onRefresh,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E8F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 18,
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
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Send item checks to branches, track actual quantities, and export results.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _Metric(label: 'Total', value: total),
          _Metric(label: 'Pending', value: pending),
          _Metric(label: 'Submitted', value: submitted),
          IconButton.filledTonal(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Export'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E8F5)),
      ),
      child: child,
    );
  }
}

class _StoreStockCheckTabs extends StatelessWidget {
  final bool showInbox;
  final int pendingCount;
  final int overdueCount;
  final ValueChanged<bool> onChanged;

  const _StoreStockCheckTabs({
    required this.showInbox,
    required this.pendingCount,
    required this.overdueCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD9E8F5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StoreStockCheckTabButton(
              selected: !showInbox,
              icon: Icons.send_rounded,
              label: 'Send To Branches',
              onTap: () => onChanged(false),
            ),
            const SizedBox(width: 6),
            _StoreStockCheckTabButton(
              selected: showInbox,
              icon: Icons.inventory_2_rounded,
              label: 'Store Inbox',
              badge: pendingCount,
              dangerBadge: overdueCount > 0,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreStockCheckTabButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final int badge;
  final bool dangerBadge;
  final VoidCallback onTap;

  const _StoreStockCheckTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    this.badge = 0,
    this.dangerBadge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF2563EB) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF334155),
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: dangerBadge
                        ? const Color(0xFFEF4444)
                        : selected
                        ? Colors.white.withValues(alpha: .20)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? Colors.white.withValues(alpha: .35)
                          : dangerBadge
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFBFDBFE),
                    ),
                  ),
                  child: Text(
                    badge > 999 ? '999+' : badge.toString(),
                    style: TextStyle(
                      color: selected || dangerBadge
                          ? Colors.white
                          : const Color(0xFF2563EB),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PanelTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _DateRangeFilterButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _DateRangeFilterButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xffF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xffE2E8F0)),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff06B6D4),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const Icon(Icons.date_range_rounded, size: 17),
          label: const Text(
            'Date Range',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _DeadlinePickerField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DeadlinePickerField({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDFA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF99F6E4)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF99F6E4)),
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  color: Color(0xFF0F766E),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Completion window',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F766E),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

enum StockCheckDateRangePickerMode { history, deadline }

class StockCheckDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange initialRange;
  final StockCheckDateRangePickerMode mode;

  const StockCheckDateRangePickerDialog({
    super.key,
    required this.initialRange,
    this.mode = StockCheckDateRangePickerMode.history,
  });

  @override
  State<StockCheckDateRangePickerDialog> createState() =>
      StockCheckDateRangePickerDialogState();
}

class StockCheckDateRangePickerDialogState
    extends State<StockCheckDateRangePickerDialog> {
  late DateTime _start;
  DateTime? _end;
  DateTime? _hoverDay;
  late DateTime _leftMonth;
  bool _selectingEnd = false;

  static const _accent = Color(0xff06B6D4);
  static const _accentBg = Color(0xffCCF2F8);
  static const _textPri = Color(0xff1E293B);
  static const _textSec = Color(0xff64748B);
  static const _textHint = Color(0xff94A3B8);
  static const _border = Color(0xffE2E8F0);
  static const _inputBg = Color(0xffF1F5F9);
  static const _surfaceBg = Color(0xffF8FAFC);

  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _start = _d(widget.initialRange.start);
    _end = _d(widget.initialRange.end);
    _leftMonth = DateTime(_start.year, _start.month);
  }

  DateTime _d(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  DateTime get _rightMonth => DateTime(_leftMonth.year, _leftMonth.month + 1);

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime day) {
    final endRef = _end ?? (_selectingEnd ? _hoverDay : null);
    if (endRef == null) return false;
    final s = _start.isBefore(endRef) ? _start : endRef;
    final e = _start.isBefore(endRef) ? endRef : _start;
    return day.isAfter(s) && day.isBefore(e);
  }

  bool _isStart(DateTime day) => _same(day, _start);
  bool _isEnd(DateTime day) {
    final endRef = _end ?? (_selectingEnd ? _hoverDay : null);
    return endRef != null && _same(day, endRef);
  }

  void _onDayTap(DateTime day) {
    setState(() {
      if (!_selectingEnd) {
        _start = day;
        _end = null;
        _selectingEnd = true;
      } else {
        if (day.isBefore(_start)) {
          _end = _start;
          _start = day;
        } else {
          _end = day;
        }
        _selectingEnd = false;
        _hoverDay = null;
      }
    });
  }

  void _onHover(DateTime? day) {
    if (_selectingEnd) setState(() => _hoverDay = day);
  }

  void _preset(DateTime s, DateTime e) {
    setState(() {
      _start = _d(s);
      _end = _d(e);
      _selectingEnd = false;
      _hoverDay = null;
      _leftMonth = DateTime(_start.year, _start.month);
    });
  }

  String _fmt(DateTime d) => '${_monthsShort[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 20,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 840,
        height: 490,
        child: Row(
          children: [
            _buildSidebar(),
            Container(width: 1, color: _border),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildMonth(_leftMonth)),
                        Container(width: 1, color: _border),
                        Expanded(child: _buildMonth(_rightMonth)),
                      ],
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final now = DateTime.now();
    final today = _d(now);
    final weekStart = today.subtract(Duration(days: today.weekday % 7));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    final presets = widget.mode == StockCheckDateRangePickerMode.deadline
        ? [
            ('Tomorrow', today, today.add(const Duration(days: 1))),
            ('3 Days', today, today.add(const Duration(days: 3))),
            ('1 Week', today, today.add(const Duration(days: 7))),
            ('2 Weeks', today, today.add(const Duration(days: 14))),
            ('1 Month', today, DateTime(now.year, now.month + 1, now.day)),
            ('2 Months', today, DateTime(now.year, now.month + 2, now.day)),
          ]
        : [
            ('Today', today, today),
            (
              'Yesterday',
              today.subtract(const Duration(days: 1)),
              today.subtract(const Duration(days: 1)),
            ),
            ('This Week', weekStart, weekEnd),
            ('Last 7 Days', today.subtract(const Duration(days: 6)), today),
            ('This Month', monthStart, monthEnd),
            ('Last 30 Days', today.subtract(const Duration(days: 29)), today),
            ('Last 3 Months', DateTime(now.year, now.month - 2, 1), monthEnd),
            ('Last 6 Months', DateTime(now.year, now.month - 5, 1), monthEnd),
          ];

    return Container(
      width: 155,
      color: _surfaceBg,
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              widget.mode == StockCheckDateRangePickerMode.deadline
                  ? 'DURATION'
                  : 'QUICK SELECT',
              style: const TextStyle(
                color: _textHint,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...presets.map((p) {
            final active =
                _end != null && _same(_start, p.$2) && _same(_end!, p.$3);
            return GestureDetector(
              onTap: () => _preset(p.$2, p.$3),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? _accent.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: active
                      ? Border.all(color: _accent.withValues(alpha: 0.3))
                      : null,
                ),
                child: Text(
                  p.$1,
                  style: TextStyle(
                    color: active ? _accent : _textPri,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final fromLabel = widget.mode == StockCheckDateRangePickerMode.deadline
        ? 'Start'
        : 'From';
    final toLabel = widget.mode == StockCheckDateRangePickerMode.deadline
        ? 'Deadline'
        : 'To';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          _navBtn(
            Icons.chevron_left,
            () => setState(
              () =>
                  _leftMonth = DateTime(_leftMonth.year, _leftMonth.month - 1),
            ),
          ),
          const SizedBox(width: 6),
          _navBtn(
            Icons.chevron_right,
            () => setState(
              () =>
                  _leftMonth = DateTime(_leftMonth.year, _leftMonth.month + 1),
            ),
          ),
          const SizedBox(width: 14),
          _dateChip(fromLabel, _fmt(_start), !_selectingEnd),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: _textHint,
            ),
          ),
          _dateChip(
            toLabel,
            _end != null
                ? _fmt(_end!)
                : _selectingEnd
                ? 'Pick end...'
                : 'Not selected',
            _selectingEnd,
            faded: _end == null,
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 18, color: _textSec),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _inputBg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _border),
        ),
        child: Icon(icon, size: 16, color: _textSec),
      ),
    );
  }

  Widget _dateChip(
    String label,
    String text,
    bool active, {
    bool faded = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: active ? _accent.withValues(alpha: 0.08) : _surfaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? _accent.withValues(alpha: 0.35) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: active ? _accent : _textHint,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            text,
            style: TextStyle(
              color: faded
                  ? _textHint
                  : active
                  ? _accent
                  : _textPri,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonth(DateTime month) {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = DateTime(month.year, month.month, 1).weekday % 7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        children: [
          Text(
            '${_months[month.month - 1]} ${month.year}',
            style: const TextStyle(
              color: _textPri,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: _weekdays
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: const TextStyle(
                          color: _textSec,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.1,
            ),
            itemCount: offset + days,
            itemBuilder: (_, i) {
              if (i < offset) return const SizedBox();
              final day = DateTime(month.year, month.month, i - offset + 1);
              return _buildCell(day);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCell(DateTime day) {
    final isStart = _isStart(day);
    final isEnd = _isEnd(day);
    final inRange = _inRange(day);
    final isFuture = day.isAfter(DateTime.now());
    final disabled =
        widget.mode == StockCheckDateRangePickerMode.history && isFuture;
    final isEdge = isStart || isEnd;

    final endRef = _end ?? (_selectingEnd ? _hoverDay : null);
    bool stripLeft = false;
    bool stripRight = false;
    if (endRef != null) {
      final s = _start.isBefore(endRef) ? _start : endRef;
      final e = _start.isBefore(endRef) ? endRef : _start;
      if (!day.isBefore(s) && !day.isAfter(e)) {
        stripLeft = !_same(day, s);
        stripRight = !_same(day, e);
      }
    }

    Color textColor = _textPri;
    if (disabled) {
      textColor = const Color(0xffCBD5E1);
    }
    if (isEdge) {
      textColor = Colors.white;
    } else if (inRange) {
      textColor = _accent;
    }

    return MouseRegion(
      onEnter: (_) => _onHover(day),
      onExit: (_) => _onHover(null),
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: disabled ? null : () => _onDayTap(day),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    color: stripLeft ? _accentBg : Colors.transparent,
                  ),
                ),
                Expanded(
                  child: Container(
                    color: stripRight ? _accentBg : Colors.transparent,
                  ),
                ),
              ],
            ),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isEdge ? _accent : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: isEdge ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          if (_end != null)
            Text(
              '${_fmt(_start)}  to  ${_fmt(_end!)}',
              style: const TextStyle(color: _textSec, fontSize: 11),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: _textSec),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _end != null
                ? () => Navigator.of(
                    context,
                  ).pop(DateTimeRange(start: _start, end: _end!))
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _border,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Apply',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeStickerOption extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BarcodeStickerOption({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? const Color(0xFFEFF6FF) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: double.infinity,
          height: 38,
          padding: const EdgeInsetsDirectional.only(start: 8, end: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: value ? const Color(0xFF93C5FD) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: value,
                onChanged: (checked) => onChanged(checked ?? false),
                activeColor: const Color(0xFF2563EB),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const Icon(
                Icons.qr_code_2_rounded,
                color: Color(0xFF2563EB),
                size: 18,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Barcode sticker',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchPickerField extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final String preview;
  final VoidCallback onTap;

  const _BranchPickerField({
    required this.selectedCount,
    required this.totalCount,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final none = selectedCount == 0;
    return Material(
      color: none ? const Color(0xFFFFF7ED) : const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: none ? const Color(0xFFFED7AA) : const Color(0xFFBFDBFE),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  color: none
                      ? const Color(0xFFEA580C)
                      : const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedCount of $totalCount destinations selected',
                      style: TextStyle(
                        color: none
                            ? const Color(0xFF9A3412)
                            : const Color(0xFF1D4ED8),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (preview.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchPickerDialog extends StatefulWidget {
  final List<String> branches;
  final Set<String> selectedBranches;

  const _BranchPickerDialog({
    required this.branches,
    required this.selectedBranches,
  });

  @override
  State<_BranchPickerDialog> createState() => _BranchPickerDialogState();
}

class _BranchPickerDialogState extends State<_BranchPickerDialog> {
  late final Set<String> _selected = {...widget.selectedBranches};
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visible = widget.branches
        .where((branch) => branch.toLowerCase().contains(query))
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 680),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Destinations',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${_selected.length} of ${widget.branches.length} selected',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search branch or store...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.backgroundWidget,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primaryColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selected
                          ..clear()
                          ..addAll(widget.branches);
                      });
                    },
                    icon: const Icon(
                      Icons.done_all_rounded,
                      color: AppColors.secondaryColor,
                    ),
                    label: const Text(
                      'Select All',
                      style: TextStyle(color: AppColors.secondaryColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(_selected.clear),
                    icon: const Icon(
                      Icons.clear_all_rounded,
                      color: AppColors.secondaryColor,
                    ),
                    label: const Text(
                      'Clear',
                      style: TextStyle(color: AppColors.secondaryColor),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Material(
                color: const Color(0xFFF8FAFC),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final branch = visible[index];
                    final selected = _selected.contains(branch);
                    final isStore = branch == _storeStockCheckDestination;
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selected.add(branch);
                          } else {
                            _selected.remove(branch);
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: Icon(
                        isStore
                            ? Icons.warehouse_rounded
                            : Icons.storefront_rounded,
                        color: isStore
                            ? const Color(0xFF059669)
                            : const Color(0xFF2563EB),
                      ),
                      title: Text(
                        isStore ? 'Store' : branch,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: isStore
                          ? const Text(
                              'Send to store team inbox',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            )
                          : null,
                      activeColor: const Color(0xFF2563EB),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Apply'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                    ),
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

class _ProductPickerField extends StatelessWidget {
  final int productCount;
  final int importCount;
  final String preview;
  final VoidCallback onTap;

  const _ProductPickerField({
    required this.productCount,
    required this.importCount,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final empty = productCount == 0 && importCount == 0;
    return Material(
      color: empty ? const Color(0xFFF8FAFC) : const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: empty ? const Color(0xFFD9E8F5) : const Color(0xFF86EFAC),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  empty ? Icons.add_box_rounded : Icons.check_circle_rounded,
                  color: empty
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF16A34A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empty ? 'Items' : 'Products selected',
                      style: TextStyle(
                        color: empty
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF166534),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  final List<_StockCheckItem> initiallySelected;

  const _ProductPickerDialog({required this.initiallySelected});

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();
  late final List<_StockCheckItem> _selected = [...widget.initiallySelected];
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final text = query.trim();
    if (text.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final safe = text.replaceAll(',', ' ');
      final res = await _client
          .from('v_item_filters_for_orders')
          .select('item_code,item_name')
          .or('item_code.ilike.%$safe%,item_name.ilike.%$safe%')
          .limit(20);
      if (!mounted) return;
      setState(() => _suggestions = List<Map<String, dynamic>>.from(res));
    } catch (_) {
      final safe = text.replaceAll(',', ' ');
      final res = await _client
          .from('item_report')
          .select('item_code,item_name')
          .or('item_code.ilike.%$safe%,item_name.ilike.%$safe%')
          .limit(20);
      if (!mounted) return;
      setState(() => _suggestions = List<Map<String, dynamic>>.from(res));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  bool _selectedHere(String code) {
    final normalized = code.trim().toLowerCase();
    return _selected.any((item) => item.itemCode.toLowerCase() == normalized);
  }

  void _add(String code, String name) {
    if (_selectedHere(code)) return;
    setState(() {
      _selected.add(_StockCheckItem(itemCode: code, itemName: name));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 760,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.add_box_rounded,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose Items',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${_selected.length} item(s) selected',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
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
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Search item code or item name...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _DialogSection(
                      title: 'Search Results',
                      child: _suggestions.isEmpty
                          ? const Center(
                              child: Text(
                                'Search to add items.',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : ListView(
                              children: _suggestions.map((item) {
                                final code = (item['item_code'] ?? '')
                                    .toString();
                                final name = (item['item_name'] ?? '')
                                    .toString();
                                final selected = _selectedHere(code);
                                return _SuggestionTile(
                                  itemCode: code,
                                  itemName: name,
                                  selected: selected,
                                  onTap: selected
                                      ? null
                                      : () => _add(code, name),
                                );
                              }).toList(),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _DialogSection(
                      title: 'Selected Items',
                      child: _selected.isEmpty
                          ? const Center(
                              child: Text(
                                'No Items selected.',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : ListView(
                              children: _selected
                                  .map(
                                    (item) => _ProductPill(
                                      item: item,
                                      onRemove: () {
                                        setState(() => _selected.remove(item));
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Apply Items'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                    ),
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

class _DialogSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _DialogSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _StockCheckBatchCard extends StatelessWidget {
  final _StockCheckBatch batch;
  final bool selected;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onEditDeadline;
  final VoidCallback onDelete;

  const _StockCheckBatchCard({
    required this.batch,
    required this.selected,
    required this.deleting,
    required this.onTap,
    required this.onEditDeadline,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final deadlineText = _deadlineText(batch.expiresAt);
    final expired = batch.isExpired;
    return Material(
      color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF93C5FD)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      batch.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Edit deadline',
                    child: IconButton(
                      onPressed: onEditDeadline,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        foregroundColor: const Color(0xFF0F766E),
                        backgroundColor: const Color(0xFFF0FDFA),
                        minimumSize: const Size(32, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Delete stock check',
                    child: IconButton(
                      onPressed: deleting ? null : onDelete,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        backgroundColor: const Color(0xFFFFF1F2),
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        disabledBackgroundColor: const Color(0xFFF1F5F9),
                        minimumSize: const Size(32, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: deleting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusDot(done: batch.pending == 0),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: expired
                      ? const Color(0xFFFFF1F2)
                      : const Color(0xFFF0FDFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: expired
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFF99F6E4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      expired ? Icons.lock_clock_rounded : Icons.timer_outlined,
                      size: 16,
                      color: expired
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        deadlineText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: expired
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF0F766E),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniStat(label: 'Branches', value: batch.branches),
                  _MiniStat(label: 'Products', value: batch.products),
                  _MiniStat(label: 'Rows', value: batch.total),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: batch.total == 0 ? 0 : batch.submitted / batch.total,
                minHeight: 7,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: const Color(0xFFE2E8F0),
                color: const Color(0xFF16A34A),
              ),
              const SizedBox(height: 8),
              Text(
                '${batch.submitted} submitted / ${batch.pending} pending',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _deadlineText(DateTime? expiresAt) {
    if (expiresAt == null) return 'No deadline set';
    final local = expiresAt.toLocal();
    final remaining = local.difference(DateTime.now());
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (remaining.isNegative) return 'Expired - deadline was $date';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final left = days > 0
        ? '${days}d ${hours}h'
        : hours > 0
        ? '${hours}h ${minutes}m'
        : '${minutes}m';
    return 'Deadline $date - $left left';
  }
}

class _DeleteStockCheckDialog extends StatelessWidget {
  final _StockCheckBatch batch;

  const _DeleteStockCheckDialog({required this.batch});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
      actionsPadding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Delete Stock Check',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${batch.title}"?',
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'This will remove ${batch.total} row(s) for ${batch.branches} branch(es). This action cannot be undone.',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Delete'),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool done;

  const _StatusDot({required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: done ? const Color(0xFF16A34A) : const Color(0xFFF97316),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final String itemCode;
  final String itemName;
  final bool selected;
  final VoidCallback? onTap;

  const _SuggestionTile({
    required this.itemCode,
    required this.itemName,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_rounded,
                    color: selected
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemCode,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        itemName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  selected ? 'Added' : 'Add',
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF2563EB),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportPreview extends StatelessWidget {
  final List<_StockCheckDraftRow> rows;
  final VoidCallback onClear;

  const _ImportPreview({required this.rows, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final branches = rows.map((e) => e.branchName).toSet().length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart_rounded, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$branches branch(es), ${rows.length} imported item(s)',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
          const SizedBox(height: 8),
          ...rows
              .take(5)
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${row.branchName}  |  ${row.itemCode}  |  ${row.itemName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          if (rows.length > 5)
            Text(
              '+${rows.length - 5} more',
              style: const TextStyle(
                color: Color(0xFF2563EB),
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductPill extends StatelessWidget {
  final _StockCheckItem item;
  final VoidCallback onRemove;

  const _ProductPill({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.itemCode}  ${item.itemName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool done;

  const _StatusChip({required this.done});

  @override
  Widget build(BuildContext context) {
    final color = done ? const Color(0xFF166534) : const Color(0xFF9A3412);
    final bg = done ? const Color(0xFFDCFCE7) : const Color(0xFFFFF7ED);
    final border = done ? const Color(0xFF86EFAC) : const Color(0xFFFED7AA);

    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Text(
        done ? 'Submitted' : 'Pending',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final bool ok;

  const _Banner({required this.message, required this.ok});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFECFDF5) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: ok ? const Color(0xFF047857) : const Color(0xFFBE123C),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Center(
        child: Text(
          'No stock checks sent yet.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
