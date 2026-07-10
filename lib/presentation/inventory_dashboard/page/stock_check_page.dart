import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/stock_check_excel_exporter.dart';
import '../../../domain/entities/stock_check_task.dart';
import '../../orders/widgets/branch_stock_check_page.dart';

const _storeStockCheckDestination = 'STORE';
const double _stockCheckAccuracyTolerance = 0.01;

class _BranchEmailContact {
  final String email;
  final String zoneManager;
  final String zoneManagerEmail;

  const _BranchEmailContact({
    required this.email,
    required this.zoneManager,
    required this.zoneManagerEmail,
  });
}

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
  String _sentSourceFilter = 'inventory';
  List<String> _branches = [];
  Map<String, _BranchEmailContact> _branchContacts = {};
  List<StockCheckTask> _sentRows = [];
  List<StockCheckTask> _visibleDetailRows = [];
  int _sentRowsVersion = 0;
  int? _batchesCacheKey;
  List<_StockCheckBatch>? _batchesCache;
  String? _selectedBatchId;
  bool _showAnalysis = false;
  final _analysisBatchIds = <String>{};
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
    _sentSourceFilter = widget.source.trim().toLowerCase();
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
      List<dynamic> branchesRes;
      try {
        branchesRes = await _client
            .from('branches')
            .select('branch_name,email,zone_manager,zone_manager_email')
            .eq('is_active', true)
            .order('branch_name');
      } catch (_) {
        branchesRes = await _client
            .from('branches')
            .select('branch_name,email')
            .eq('is_active', true)
            .order('branch_name');
      }

      var sentRows = <StockCheckTask>[];
      String tableError = '';
      try {
        final rows = await _client
            .from('stock_check_tasks')
            .select()
            .inFilter(
              'source',
              _canSendToStore ? ['inventory', 'store'] : [widget.source],
            )
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
        final branchContacts = <String, _BranchEmailContact>{};
        for (final branch in List<Map<String, dynamic>>.from(branchesRes)) {
          final name = (branch['branch_name'] ?? '').toString().trim();
          final email = (branch['email'] ?? '').toString().trim();
          if (name.isNotEmpty && email.isNotEmpty) {
            branchContacts[name] = _BranchEmailContact(
              email: email,
              zoneManager: (branch['zone_manager'] ?? '').toString().trim(),
              zoneManagerEmail: (branch['zone_manager_email'] ?? '')
                  .toString()
                  .trim(),
            );
          }
        }
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
        _branchContacts = branchContacts;
        _sentRows = sentRows;
        _sentRowsVersion++;
        _batchesCacheKey = null;
        _batchesCache = null;
        final visibleSentRows = sentRows.where((row) {
          return row.source.trim().toLowerCase() ==
              _sentSourceFilter.trim().toLowerCase();
        }).toList();
        if (_selectedBatchId == null ||
            !visibleSentRows.any((row) => row.batchId == _selectedBatchId)) {
          _selectedBatchId = visibleSentRows.isEmpty
              ? null
              : visibleSentRows.first.batchId;
        }
        final visibleBatchIds = visibleSentRows
            .map((row) => row.batchId)
            .toSet();
        _analysisBatchIds.removeWhere((id) => !visibleBatchIds.contains(id));
        if (_analysisBatchIds.isEmpty && _selectedBatchId != null) {
          _analysisBatchIds.add(_selectedBatchId!);
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
        _sentRowsVersion++;
        _batchesCacheKey = null;
        _batchesCache = null;
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
    final cacheKey = Object.hash(
      _sentRowsVersion,
      _sentSourceFilter,
      _sentFrom.millisecondsSinceEpoch,
      _sentTo.millisecondsSinceEpoch,
    );
    if (_batchesCacheKey == cacheKey && _batchesCache != null) {
      return _batchesCache!;
    }
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
    _batchesCacheKey = cacheKey;
    _batchesCache = batches;
    return batches;
  }

  List<StockCheckTask> _filteredSentRows() {
    return _sentRows.where((row) {
      if (row.source.trim().toLowerCase() !=
          _sentSourceFilter.trim().toLowerCase()) {
        return false;
      }
      final sentAt = row.sentAt;
      if (sentAt == null) return false;
      return !sentAt.isBefore(_sentFrom) && !sentAt.isAfter(_sentTo);
    }).toList();
  }

  int _sourceBatchCount(String source) {
    return _sentRows
        .where((row) => row.source.trim().toLowerCase() == source)
        .map((row) => row.batchId)
        .toSet()
        .length;
  }

  List<StockCheckTask> _selectedBatchRows(List<_StockCheckBatch> batches) {
    if (batches.isEmpty) return const [];
    final selected = batches.where((e) => e.id == _selectedBatchId);
    return selected.isEmpty ? batches.first.rows : selected.first.rows;
  }

  List<StockCheckTask> _selectedAnalysisRows(List<_StockCheckBatch> batches) {
    if (batches.isEmpty) return const [];
    final ids = _analysisBatchIds.isEmpty
        ? {_selectedBatchId ?? batches.first.id}
        : _analysisBatchIds;
    return batches
        .where((batch) => ids.contains(batch.id))
        .expand((batch) => batch.rows)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleSourceRows = _sentRows.where((row) {
      return row.source.trim().toLowerCase() ==
          _sentSourceFilter.trim().toLowerCase();
    }).toList();
    final pending = visibleSourceRows.where((e) => e.isPending).length;
    final submitted = visibleSourceRows.where((e) => e.isSubmitted).length;
    final batches = _batches();
    final selectedRows = _selectedBatchRows(batches);
    final selectedAnalysisRows = _selectedAnalysisRows(batches);

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
                    total: visibleSourceRows.length,
                    onRefresh: _load,
                    onExport: selectedRows.isEmpty
                        ? null
                        : () {
                            if (_showAnalysis) {
                              StockCheckExcelExporter.exportAnalysis(
                                rows: selectedAnalysisRows,
                                title: 'Stock Check Accuracy Analysis',
                              );
                              return;
                            }
                            StockCheckExcelExporter.export(
                              rows: _visibleDetailRows.isEmpty
                                  ? selectedRows
                                  : _visibleDetailRows,
                              title: selectedRows.first.title,
                            );
                          },
                  );

                  if (_showStoreInbox && _hasStoreInbox) {
                    return Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          _StockCheckTopTabs(
                            analysis: _showAnalysis,
                            onChanged: (value) {
                              setState(() => _showAnalysis = value);
                            },
                          ),
                          const SizedBox(height: 16),
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
                  final analysisHeight = math.max(
                    760.0,
                    constraints.maxHeight - 150,
                  );
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        _StockCheckTopTabs(
                          analysis: _showAnalysis,
                          onChanged: (value) {
                            setState(() {
                              _showAnalysis = value;
                              if (_showAnalysis &&
                                  _analysisBatchIds.isEmpty &&
                                  batches.isNotEmpty) {
                                _analysisBatchIds.add(
                                  _selectedBatchId ?? batches.first.id,
                                );
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        if (!_showAnalysis) ...[
                          header,
                          const SizedBox(height: 16),
                        ],
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
                        if (_showAnalysis)
                          SizedBox(
                            height: analysisHeight,
                            child: _StockCheckAnalysisPanel(
                              batches: batches,
                              selectedBatchIds: _analysisBatchIds,
                              rows: selectedAnalysisRows,
                              branchContacts: _branchContacts,
                              onSelectBatches: () =>
                                  _openAnalysisBatchPicker(batches),
                            ),
                          )
                        else ...[
                          _buildComposer(),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: workspaceHeight,
                            child: _buildWorkspace(
                              batches,
                              selectedRows,
                              selectedAnalysisRows,
                            ),
                          ),
                        ],
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
    List<StockCheckTask> selectedAnalysisRows,
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
                if (_canSendToStore) ...[
                  _SentSourceToggle(
                    value: _sentSourceFilter,
                    inventoryCount: _sourceBatchCount('inventory'),
                    storeCount: _sourceBatchCount('store'),
                    onChanged: (value) {
                      setState(() {
                        _sentSourceFilter = value;
                        _selectedBatchId = null;
                        _visibleDetailRows = [];
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                ],
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
                        onTap: () => setState(() {
                          _selectedBatchId = batch.id;
                          _visibleDetailRows = [];
                          if (!_showAnalysis) {
                            _analysisBatchIds
                              ..clear()
                              ..add(batch.id);
                          }
                        }),
                        canManage:
                            _sentSourceFilter == widget.source.toLowerCase(),
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
        Expanded(
          child: _showAnalysis
              ? _StockCheckAnalysisPanel(
                  batches: batches,
                  selectedBatchIds: _analysisBatchIds,
                  rows: selectedAnalysisRows,
                  branchContacts: _branchContacts,
                  onSelectBatches: () => _openAnalysisBatchPicker(batches),
                )
              : _StockCheckResultTable(
                  rows: selectedRows,
                  onFilteredRowsChanged: (rows) {
                    _visibleDetailRows = rows;
                  },
                  onRowUpdated: _replaceSentRow,
                ),
        ),
      ],
    );
  }

  void _replaceSentRow(StockCheckTask updated) {
    setState(() {
      final index = _sentRows.indexWhere((row) => row.id == updated.id);
      if (index >= 0) {
        _sentRows[index] = updated;
        _sentRowsVersion++;
        _batchesCacheKey = null;
        _batchesCache = null;
      }
    });
  }

  Future<void> _openAnalysisBatchPicker(List<_StockCheckBatch> batches) async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _AnalysisBatchPickerDialog(
        batches: batches,
        selectedBatchIds: _analysisBatchIds,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _analysisBatchIds
        ..clear()
        ..addAll(selected.isEmpty ? {batches.first.id} : selected);
    });
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
  final ValueChanged<List<StockCheckTask>>? onFilteredRowsChanged;
  final ValueChanged<StockCheckTask>? onRowUpdated;

  const _StockCheckResultTable({
    required this.rows,
    this.onFilteredRowsChanged,
    this.onRowUpdated,
  });

  @override
  State<_StockCheckResultTable> createState() => _StockCheckResultTableState();
}

class _StockCheckAnalysisPanel extends StatefulWidget {
  final List<_StockCheckBatch> batches;
  final Set<String> selectedBatchIds;
  final List<StockCheckTask> rows;
  final Map<String, _BranchEmailContact> branchContacts;
  final VoidCallback onSelectBatches;

  const _StockCheckAnalysisPanel({
    required this.batches,
    required this.selectedBatchIds,
    required this.rows,
    required this.branchContacts,
    required this.onSelectBatches,
  });

  @override
  State<_StockCheckAnalysisPanel> createState() =>
      _StockCheckAnalysisPanelState();
}

class _StockCheckAnalysisPanelState extends State<_StockCheckAnalysisPanel> {
  final _searchController = TextEditingController();
  List<StockCheckTask>? _cachedRows;
  _StockCheckAnalysisReport? _cachedReport;
  String _search = '';
  String _status = 'ALL';
  String _accuracyBand = 'ALL';
  String _analysisBranch = 'ALL';
  String _sortBy = 'accuracy';
  bool _sortDescending = false;
  bool _exporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  _StockCheckAnalysisReport _reportFor(List<StockCheckTask> rows) {
    if (identical(_cachedRows, rows) && _cachedReport != null) {
      return _cachedReport!;
    }
    _cachedRows = rows;
    _cachedReport = _StockCheckAnalysisReport(rows);
    return _cachedReport!;
  }

  @override
  Widget build(BuildContext context) {
    final report = _reportFor(widget.rows);
    final availableBranches = report.branches.map((e) => e.branch).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final selectedBranch = availableBranches.contains(_analysisBranch)
        ? _analysisBranch
        : 'ALL';
    var branches = report.branches;
    final needle = _search.trim().toLowerCase();
    branches = branches.where((branch) {
      final branchOk =
          selectedBranch == 'ALL' || branch.branch == selectedBranch;
      final statusOk = switch (_status) {
        'warning' => branch.hasDeadlineRisk,
        'incomplete' => branch.pending > 0,
        'complete' => branch.pending == 0,
        _ => true,
      };
      final accuracyOk = switch (_accuracyBand) {
        'gte75' => branch.accuracyRate >= 75,
        'lt75' => branch.accuracyRate < 75,
        _ => true,
      };
      final searchOk =
          needle.isEmpty || branch.branch.toLowerCase().contains(needle);
      return branchOk && statusOk && accuracyOk && searchOk;
    }).toList();
    branches.sort((a, b) {
      final aValue = _sortBy == 'completion'
          ? a.completionRate
          : a.accuracyRate;
      final bValue = _sortBy == 'completion'
          ? b.completionRate
          : b.accuracyRate;
      final primary = aValue.compareTo(bValue);
      if (primary != 0) return _sortDescending ? -primary : primary;
      if (a.hasDeadlineRisk != b.hasDeadlineRisk) {
        return a.hasDeadlineRisk ? -1 : 1;
      }
      return a.branch.toLowerCase().compareTo(b.branch.toLowerCase());
    });
    final notStartedReminderBranches = report.branches
        .where((branch) => branch.submitted == 0 && branch.pending > 0)
        .toList();
    final notFinishedReminderBranches = report.branches
        .where((branch) => branch.submitted > 0 && branch.pending > 0)
        .toList();

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _AnalysisHeaderSummary(
                  report: report,
                  selectedProjects: widget.selectedBatchIds.length,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.onSelectBatches,
                      icon: const Icon(
                        Icons.rule_folder_rounded,
                        color: AppColors.secondaryColor,
                      ),
                      label: Text(
                        '${widget.selectedBatchIds.length} Project(s)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.secondaryColor,
                        ),
                      ),
                    ),
                    _BulkReminderButton(
                      label: 'Email Not Started',
                      count: notStartedReminderBranches.length,
                      icon: Icons.forward_to_inbox_rounded,
                      color: const Color(0xFFEA580C),
                      onPressed: notStartedReminderBranches.isEmpty
                          ? null
                          : () => _openBulkReminderEmail(
                              branches: notStartedReminderBranches,
                              type: _BulkReminderType.notStarted,
                            ),
                    ),
                    _BulkReminderButton(
                      label: 'Email Not Finished',
                      count: notFinishedReminderBranches.length,
                      icon: Icons.mark_email_unread_rounded,
                      color: const Color(0xFFDC2626),
                      onPressed: notFinishedReminderBranches.isEmpty
                          ? null
                          : () => _openBulkReminderEmail(
                              branches: notFinishedReminderBranches,
                              type: _BulkReminderType.notFinished,
                            ),
                    ),
                    FilledButton.icon(
                      onPressed: widget.rows.isEmpty || _exporting
                          ? null
                          : _exportAnalysis,
                      icon: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        _exporting ? 'Preparing...' : 'Export Report',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AnalysisProjectStrip(
                  batches: widget.batches
                      .where(
                        (batch) => widget.selectedBatchIds.contains(batch.id),
                      )
                      .toList(),
                  onTap: widget.onSelectBatches,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 320,
                child: _AnalysisBranchPicker(
                  value: selectedBranch,
                  branches: availableBranches,
                  onChanged: (value) {
                    setState(() {
                      _analysisBranch = value;
                      _search = '';
                      _searchController.clear();
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _AnalysisMetricCard(
                label: 'Overall accuracy',
                value: '${report.accuracyRate.toStringAsFixed(1)}%',
                icon: Icons.verified_rounded,
                color: _scoreColor(report.accuracyRate),
              ),
              const SizedBox(width: 10),
              _AnalysisMetricCard(
                label: 'Completion',
                value: '${report.completionRate.toStringAsFixed(1)}%',
                icon: Icons.task_alt_rounded,
                color: AppColors.primaryColor,
              ),
              const SizedBox(width: 10),
              _AnalysisMetricCard(
                label: 'Different items',
                value: report.different.toString(),
                icon: Icons.troubleshoot_rounded,
                color: const Color(0xFFF97316),
              ),
              const SizedBox(width: 10),
              _AnalysisMetricCard(
                label: 'Branches at risk',
                value: report.riskyBranches.toString(),
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFDC2626),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _AnalysisMetricCard(
                label: 'Not started branches',
                value: report.notStartedBranches.toString(),
                icon: Icons.flag_circle_rounded,
                color: const Color(0xFF64748B),
              ),
              const SizedBox(width: 10),
              _AnalysisMetricCard(
                label: 'Completed branches',
                value: report.completedBranches.toString(),
                icon: Icons.verified_user_rounded,
                color: const Color(0xFF16A34A),
              ),
              const SizedBox(width: 10),
              _AnalysisMetricCard(
                label: 'Non-zero checked',
                value: report.nonZeroCounted.toString(),
                icon: Icons.dataset_rounded,
                color: const Color(0xFF7C3AED),
              ),
              const SizedBox(width: 10),
              _AnalysisMetricCard(
                label: 'Below 75%',
                value: report.below75Branches.toString(),
                icon: Icons.trending_down_rounded,
                color: const Color(0xFFEA580C),
              ),
            ],
          ),
          _AnalysisToolbar(
            searchController: _searchController,
            status: _status,
            accuracyBand: _accuracyBand,
            sortBy: _sortBy,
            sortDescending: _sortDescending,
            onSearchChanged: (value) => setState(() => _search = value),
            onStatusChanged: (value) => setState(() => _status = value),
            onAccuracyBandChanged: (value) {
              setState(() => _accuracyBand = value);
            },
            onSortChanged: (value) => setState(() => _sortBy = value),
            onDirectionToggle: () {
              setState(() => _sortDescending = !_sortDescending);
            },
          ),
          const SizedBox(height: 12),
          if (report.comparisonRows.isNotEmpty) ...[
            _ComparisonSummary(rows: report.comparisonRows.take(4).toList()),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: branches.isEmpty
                ? const Center(
                    child: Text(
                      'No branch analysis available for the selected projects.',
                      style: TextStyle(
                        color: AppColors.subText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: branches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _BranchAccuracyCard(
                        rank: index + 1,
                        row: branches[index],
                        contact: widget.branchContacts[branches[index].branch],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _scoreColor(double value) {
    if (value >= 95) return const Color(0xFF16A34A);
    if (value >= 85) return AppColors.primaryColor;
    if (value >= 70) return const Color(0xFFF97316);
    return const Color(0xFFDC2626);
  }

  Future<void> _exportAnalysis() async {
    setState(() => _exporting = true);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      await StockCheckExcelExporter.exportAnalysis(
        rows: widget.rows,
        title: 'Stock Check Accuracy Analysis',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openBulkReminderEmail({
    required List<_StockCheckBranchAnalysis> branches,
    required _BulkReminderType type,
  }) async {
    final branchContacts = branches
        .map((branch) => widget.branchContacts[branch.branch])
        .whereType<_BranchEmailContact>()
        .where((contact) => contact.email.trim().isNotEmpty)
        .toList();
    final toEmails = _distinctEmails(
      branchContacts.map((contact) => contact.email),
    );
    if (toEmails.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No branch emails found for the selected reminder.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final ccEmails = _distinctEmails([
      'Inventory@alain-pharmacy.com',
      'ahmad.alkouz@alain-pharmacy.com',
      ...branchContacts.map((contact) => contact.zoneManagerEmail),
    ]);
    final projectLabel =
        widget.selectedBatchIds.length == 1 && widget.rows.isNotEmpty
        ? widget.rows.first.title
        : '${widget.selectedBatchIds.length} stock check projects';
    final subject = switch (type) {
      _BulkReminderType.notStarted =>
        'Stock Check Reminder - Not Started - $projectLabel',
      _BulkReminderType.notFinished =>
        'Stock Check Reminder - Not Finished - $projectLabel',
    };
    final body = switch (type) {
      _BulkReminderType.notStarted =>
        'Dear Team,\n\n'
            'Our records show that your branch has not started the assigned Stock Check yet.\n'
            'Please open the Stock Check page, enter the required quantities, and submit the completed items as soon as possible.\n\n'
            'Thank you.',
      _BulkReminderType.notFinished =>
        'Dear Team,\n\n'
            'Our records show that your branch started the assigned Stock Check but has not completed it yet.\n'
            'Please continue the remaining items and submit the completed stock check as soon as possible.\n\n'
            'Thank you.',
    };
    final uri = Uri(
      scheme: 'mailto',
      path: toEmails.join(','),
      queryParameters: {
        'subject': subject,
        'body': body,
        'cc': ccEmails.join(','),
      },
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the email app.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  List<String> _distinctEmails(Iterable<String> emails) {
    final seen = <String>{};
    final result = <String>[];
    for (final email in emails) {
      final value = email.trim();
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (seen.add(key)) result.add(value);
    }
    return result;
  }
}

class _AnalysisProjectStrip extends StatelessWidget {
  final List<_StockCheckBatch> batches;
  final VoidCallback onTap;

  const _AnalysisProjectStrip({required this.batches, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = batches.isEmpty
        ? 'Choose projects to compare'
        : batches.map((batch) => batch.title).take(3).join(' - ');
    return Material(
      color: const Color(0xFFF0FDFA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF99F6E4)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.compare_arrows_rounded,
                color: Color(0xFF0F766E),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w900,
                  ),
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

class _AnalysisBranchPicker extends StatelessWidget {
  final String value;
  final List<String> branches;
  final ValueChanged<String> onChanged;

  const _AnalysisBranchPicker({
    required this.value,
    required this.branches,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = value == 'ALL' ? 'All branches' : value;
    return InkWell(
      onTap: () async {
        final selected = await showDialog<String>(
          context: context,
          builder: (_) =>
              _AnalysisBranchSearchDialog(branches: branches, selected: value),
        );
        if (selected != null) onChanged(selected);
      },
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: _StockCheckResultTableState._filterDecoration(
          'Branch Filter',
          icon: Icons.storefront_rounded,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const Icon(Icons.search_rounded, color: AppColors.subText),
          ],
        ),
      ),
    );
  }
}

class _AnalysisBranchSearchDialog extends StatefulWidget {
  final List<String> branches;
  final String selected;

  const _AnalysisBranchSearchDialog({
    required this.branches,
    required this.selected,
  });

  @override
  State<_AnalysisBranchSearchDialog> createState() =>
      _AnalysisBranchSearchDialogState();
}

class _AnalysisBranchSearchDialogState
    extends State<_AnalysisBranchSearchDialog> {
  final _controller = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _search.trim().toLowerCase();
    final options = [
      'ALL',
      ...widget.branches.where(
        (branch) => needle.isEmpty || branch.toLowerCase().contains(needle),
      ),
    ];
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 430,
        height: 520,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Filter on branch',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                decoration: _StockCheckResultTableState._filterDecoration(
                  'Search branch',
                  icon: Icons.search_rounded,
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: options.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final branch = options[index];
                    final selected = branch == widget.selected;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: AppColors.primaryColor.withValues(
                        alpha: .08,
                      ),
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: selected
                            ? AppColors.primaryColor
                            : AppColors.subText,
                      ),
                      title: Text(
                        branch == 'ALL' ? 'All branches' : branch,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      onTap: () => Navigator.pop(context, branch),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalysisHeaderSummary extends StatelessWidget {
  final _StockCheckAnalysisReport report;
  final int selectedProjects;

  const _AnalysisHeaderSummary({
    required this.report,
    required this.selectedProjects,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.analytics_rounded,
            color: AppColors.primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Stock Check Accuracy Analysis',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                '$selectedProjects project(s) • ${report.branches.length} branch(es) • ${report.submitted} submitted item(s)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.subText,
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

class _AnalysisToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final String status;
  final String accuracyBand;
  final String sortBy;
  final bool sortDescending;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onAccuracyBandChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onDirectionToggle;

  const _AnalysisToolbar({
    required this.searchController,
    required this.status,
    required this.accuracyBand,
    required this.sortBy,
    required this.sortDescending,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onAccuracyBandChanged,
    required this.onSortChanged,
    required this.onDirectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 320,
            height: 44,
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search branch',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFD9E8F5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFD9E8F5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.primaryColor,
                    width: 1.4,
                  ),
                ),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 12),
          _ToolbarGroup(
            label: 'View',
            children: [
              _ToolbarChip(
                label: 'All',
                icon: Icons.grid_view_rounded,
                selected: status == 'ALL',
                onTap: () => onStatusChanged('ALL'),
              ),
              _ToolbarChip(
                label: 'Attention',
                icon: Icons.warning_amber_rounded,
                selected: status == 'warning',
                danger: true,
                onTap: () => onStatusChanged('warning'),
              ),
              _ToolbarChip(
                label: 'Pending',
                icon: Icons.hourglass_bottom_rounded,
                selected: status == 'incomplete',
                onTap: () => onStatusChanged('incomplete'),
              ),
              _ToolbarChip(
                label: 'Completed',
                icon: Icons.check_circle_outline_rounded,
                selected: status == 'complete',
                onTap: () => onStatusChanged('complete'),
              ),
            ],
          ),
          const SizedBox(width: 12),
          _ToolbarGroup(
            label: 'Accuracy',
            children: [
              _ToolbarChip(
                label: 'All',
                icon: Icons.all_inclusive_rounded,
                selected: accuracyBand == 'ALL',
                onTap: () => onAccuracyBandChanged('ALL'),
              ),
              _ToolbarChip(
                label: '75%+',
                icon: Icons.trending_up_rounded,
                selected: accuracyBand == 'gte75',
                onTap: () => onAccuracyBandChanged('gte75'),
              ),
              _ToolbarChip(
                label: 'Below 75%',
                icon: Icons.trending_down_rounded,
                selected: accuracyBand == 'lt75',
                danger: true,
                onTap: () => onAccuracyBandChanged('lt75'),
              ),
            ],
          ),
          const Spacer(),
          _ToolbarGroup(
            label: 'Sort',
            children: [
              _ToolbarChip(
                label: 'Accuracy',
                icon: Icons.verified_rounded,
                selected: sortBy == 'accuracy',
                onTap: () => onSortChanged('accuracy'),
              ),
              _ToolbarChip(
                label: 'Completion',
                icon: Icons.task_alt_rounded,
                selected: sortBy == 'completion',
                onTap: () => onSortChanged('completion'),
              ),
              Tooltip(
                message: sortDescending
                    ? 'Showing highest values first'
                    : 'Showing lowest values first',
                child: InkWell(
                  onTap: onDirectionToggle,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryColor,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sortDescending
                              ? Icons.south_rounded
                              : Icons.north_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          sortDescending ? 'High first' : 'Low first',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolbarGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _ToolbarGroup({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.subText,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFD9E8F5)),
          ),
          child: Row(children: children),
        ),
      ],
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  const _ToolbarChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final selectedColor = danger
        ? const Color(0xFFDC2626)
        : AppColors.primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? selectedColor.withValues(alpha: .12)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? selectedColor : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? selectedColor : AppColors.subText,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: selected ? selectedColor : AppColors.secondaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalysisMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _AnalysisMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .35)),
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
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.subText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
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

class _ComparisonSummary extends StatelessWidget {
  final List<_StockCheckComparisonRow> rows;

  const _ComparisonSummary({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Project comparison by branch',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      row.branch,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${row.firstAccuracy.toStringAsFixed(1)}% → ${row.lastAccuracy.toStringAsFixed(1)}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${row.delta >= 0 ? '+' : ''}${row.delta.toStringAsFixed(1)} pts',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: row.delta >= 0
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Common ${row.commonItems} • Improved ${row.improved} • Worse ${row.worsened}',
                    style: const TextStyle(
                      color: AppColors.subText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchAccuracyCard extends StatelessWidget {
  final int rank;
  final _StockCheckBranchAnalysis row;
  final _BranchEmailContact? contact;

  const _BranchAccuracyCard({
    required this.rank,
    required this.row,
    required this.contact,
  });

  @override
  Widget build(BuildContext context) {
    final accuracyColor = row.accuracyRate >= 95
        ? const Color(0xFF16A34A)
        : row.accuracyRate >= 80
        ? AppColors.primaryColor
        : row.accuracyRate >= 60
        ? const Color(0xFFF97316)
        : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: row.hasDeadlineRisk ? const Color(0xFFFFF1F2) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: row.hasDeadlineRisk
              ? const Color(0xFFFCA5A5)
              : const Color(0xFFD9E8F5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accuracyColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              '#$rank',
              style: TextStyle(
                color: accuracyColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.branch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${row.submitted} submitted / ${row.pending} pending • ${row.nonZeroCounted} non-zero • ${row.toleranceCorrect} within tolerance',
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _AnalysisBar(
              label: 'Accuracy',
              value: row.accuracyRate / 100,
              text:
                  '${row.accuracyRate.toStringAsFixed(1)}% (${row.correct}/${row.counted})',
              color: accuracyColor,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 2,
            child: _AnalysisBar(
              label: 'Completion',
              value: row.completionRate / 100,
              text: '${row.completionRate.toStringAsFixed(1)}%',
              color: row.hasDeadlineRisk
                  ? const Color(0xFFDC2626)
                  : AppColors.primaryColor,
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 178,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${row.different} different',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  row.hasDeadlineRisk
                      ? 'Needs action within 2 days'
                      : 'On track',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: row.hasDeadlineRisk
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF16A34A),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if ((contact?.email ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _EmailReminderButton(branch: row.branch, contact: contact!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailReminderButton extends StatelessWidget {
  final String branch;
  final _BranchEmailContact contact;

  const _EmailReminderButton({required this.branch, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open Outlook reminder email',
      child: InkWell(
        onTap: () => _openReminderEmail(context),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.primaryColor.withValues(alpha: .28),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mark_email_unread_rounded,
                size: 15,
                color: AppColors.primaryColor,
              ),
              SizedBox(width: 5),
              Text(
                'Email reminder',
                style: TextStyle(
                  color: AppColors.primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openReminderEmail(BuildContext context) async {
    final cc = <String>[
      'Inventory@alain-pharmacy.com',
      'ahmad.alkouz@alain-pharmacy.com',
      if (contact.zoneManagerEmail.trim().isNotEmpty)
        contact.zoneManagerEmail.trim(),
    ];
    final body =
        'Dear $branch Team,\n\n'
        'Please complete the pending Stock Check as soon as possible.\n'
        'Kindly enter the required System Qty and Actual Qty, then submit the stock check from the branch dashboard.\n\n'
        'Thank you.';
    final subject = Uri.encodeComponent('Stock Check Reminder - $branch');

    final bodyEncoded = Uri.encodeComponent(body);

    final ccEncoded = Uri.encodeComponent(cc.join(';'));

    final mailto =
        'mailto:${contact.email}'
        '?subject=$subject'
        '&body=$bodyEncoded'
        '&cc=$ccEncoded';

    final opened = await launchUrl(
      Uri.parse(mailto),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open email app for ${contact.email}'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }
}

enum _BulkReminderType { notStarted, notFinished }

class _BulkReminderButton extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _BulkReminderButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: onPressed == null ? null : color),
      label: Text(
        '$label ($count)',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: onPressed == null ? null : color,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: const Color(0xFF94A3B8),
        side: BorderSide(
          color: onPressed == null
              ? const Color(0xFFE2E8F0)
              : color.withValues(alpha: .55),
        ),
        backgroundColor: onPressed == null
            ? const Color(0xFFF8FAFC)
            : color.withValues(alpha: .07),
      ),
    );
  }
}

class _AnalysisBar extends StatelessWidget {
  final String label;
  final double value;
  final String text;
  final Color color;

  const _AnalysisBar({
    required this.label,
    required this.value,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.subText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 7),
        LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: 8,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: const Color(0xFFE2E8F0),
          color: color,
        ),
      ],
    );
  }
}

class _StockCheckResultTableState extends State<_StockCheckResultTable> {
  final _searchController = TextEditingController();
  final _horizontalTableController = ScrollController();
  String _search = '';
  final _branchFilters = <String>{};
  String _statusFilter = 'ALL';
  String _sortColumn = 'branch';
  bool _sortAscending = true;
  final _columnFilters = <String, Set<String>>{};
  final _numericFilters = <String, _NumericColumnFilter>{};
  List<String> _branches = const [];
  List<StockCheckTask> _filteredRows = const [];
  bool _showBarcodeSticker = false;
  int? _lastNotifiedRowsHash;
  int? _rowIndexCacheKey;
  List<String> _cachedBranches = const [];
  bool _cachedShowBarcodeSticker = false;

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
      _branchFilters.clear();
      _statusFilter = 'ALL';
      _sortColumn = 'branch';
      _sortAscending = true;
      _columnFilters.clear();
      _numericFilters.clear();
      _lastNotifiedRowsHash = null;
    }
    _rebuildIndexes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalTableController.dispose();
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
                  width: 300.w,
                  child: _SearchableBranchFilter(
                    selectedBranches: _branchFilters,
                    branches: _branches,
                    onChanged: (value) {
                      setState(() {
                        _branchFilters
                          ..clear()
                          ..addAll(value);
                        _rebuildIndexes();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    decoration: _filterDecoration('Status'),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All status')),
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: 'submitted',
                        child: Text('Submitted'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _statusFilter = value ?? 'ALL';
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
                if (_filteredRows.isNotEmpty) ...[
                  _TablePanButton(
                    icon: Icons.keyboard_arrow_left_rounded,
                    tooltip: 'Scroll table left',
                    onPressed: () => _scrollTableHorizontally(-420),
                  ),
                  const SizedBox(width: 6),
                  _TablePanButton(
                    icon: Icons.keyboard_arrow_right_rounded,
                    tooltip: 'Scroll table right',
                    onPressed: () => _scrollTableHorizontally(420),
                  ),
                  const SizedBox(width: 12),
                ],
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
                : Scrollbar(
                    controller: _horizontalTableController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _horizontalTableController,
                      scrollDirection: Axis.horizontal,
                      child: _FastStockCheckResultsTable(
                        rows: _filteredRows,
                        showBarcodeSticker: _showBarcodeSticker,
                        activeFilters: {
                          ..._columnFilters.keys,
                          ..._numericFilters.keys,
                        },
                        sortColumn: _sortColumn,
                        sortAscending: _sortAscending,
                        onColumnFilter: _openColumnFilter,
                        onRowTap: _openNoteDialog,
                      ),
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

  void _scrollTableHorizontally(double delta) {
    if (!_horizontalTableController.hasClients) return;
    final next = (_horizontalTableController.offset + delta).clamp(
      0.0,
      _horizontalTableController.position.maxScrollExtent,
    );
    _horizontalTableController.animateTo(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _rebuildIndexes() {
    final rowIndexKey = _rowsIndexKey(widget.rows);
    if (_rowIndexCacheKey != rowIndexKey) {
      _rowIndexCacheKey = rowIndexKey;
      _cachedBranches =
          widget.rows
              .map((row) => row.branchName.trim())
              .where((branch) => branch.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _cachedShowBarcodeSticker = widget.rows.any(
        (row) => row.includeBarcodeStickerCheck,
      );
    }
    final branches = _cachedBranches;

    _branchFilters.removeWhere((branch) => !branches.contains(branch));

    final needle = _search.trim().toLowerCase();
    final filtered =
        widget.rows.where((row) {
          final branchOk =
              _branchFilters.isEmpty ||
              _branchFilters.contains(row.branchName.trim());
          final statusOk =
              _statusFilter == 'ALL' ||
              (_statusFilter == 'submitted' && row.isSubmitted) ||
              (_statusFilter == 'pending' && row.isPending);
          final searchOk =
              needle.isEmpty ||
              row.branchName.toLowerCase().contains(needle) ||
              row.itemCode.toLowerCase().contains(needle) ||
              row.itemName.toLowerCase().contains(needle);
          final columnOk = _columnFilters.entries.every((entry) {
            final selected = entry.value;
            if (selected.isEmpty) return true;
            return selected.contains(_columnValue(row, entry.key));
          });
          final numberOk = _numericFilters.entries.every((entry) {
            return entry.value.matches(_numericColumnValue(row, entry.key));
          });
          return branchOk && statusOk && searchOk && columnOk && numberOk;
        }).toList()..sort((a, b) {
          final primary = _compareColumn(a, b, _sortColumn);
          if (primary != 0) return _sortAscending ? primary : -primary;
          final branch = _compareColumn(a, b, 'branch');
          if (branch != 0) return branch;
          final name = _compareColumn(a, b, 'itemName');
          if (name != 0) return name;
          return _compareColumn(a, b, 'itemCode');
        });

    _branches = branches;
    _filteredRows = filtered;
    _showBarcodeSticker = _cachedShowBarcodeSticker;
    final rowsHash = Object.hashAll(_filteredRows.map((row) => row.id));
    if (_lastNotifiedRowsHash != rowsHash) {
      _lastNotifiedRowsHash = rowsHash;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFilteredRowsChanged?.call(_filteredRows);
      });
    }
  }

  int _rowsIndexKey(List<StockCheckTask> rows) {
    if (rows.isEmpty) return 0;
    return Object.hash(
      rows.length,
      rows.first.id,
      rows.last.id,
      rows.first.batchId,
    );
  }

  static InputDecoration _filterDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: AppColors.backgroundWidget,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

  static String _yesNo(bool? value) {
    if (value == null) return '';
    return value ? 'Yes' : 'No';
  }

  int _compareColumn(StockCheckTask a, StockCheckTask b, String column) {
    if (column == 'system' || column == 'actual' || column == 'diff') {
      num? number(StockCheckTask row) => switch (column) {
        'system' => row.systemQty,
        'actual' => row.actualQty,
        _ => row.variance,
      };
      final av = number(a);
      final bv = number(b);
      if (av == null && bv == null) return 0;
      if (av == null) return -1;
      if (bv == null) return 1;
      return av.compareTo(bv);
    }
    return _columnValue(
      a,
      column,
    ).toLowerCase().compareTo(_columnValue(b, column).toLowerCase());
  }

  String _columnValue(StockCheckTask row, String column) {
    return switch (column) {
      'branch' => row.branchName,
      'itemCode' => row.itemCode,
      'itemName' => row.itemName,
      'system' => row.systemQty?.toString() ?? '',
      'actual' => row.actualQty?.toString() ?? '',
      'diff' => row.variance?.toString() ?? '',
      'barcode' =>
        row.includeBarcodeStickerCheck
            ? _yesNo(row.barcodeStickerIsCorrect)
            : '',
      'submittedByName' => row.submittedByName,
      'submittedByEmployeeId' => row.submittedByEmployeeId,
      'note' => row.note,
      'status' => row.isSubmitted ? 'Submitted' : 'Pending',
      _ => '',
    };
  }

  num? _numericColumnValue(StockCheckTask row, String column) {
    return switch (column) {
      'system' => row.systemQty,
      'actual' => row.actualQty,
      'diff' => row.variance,
      _ => null,
    };
  }

  Future<void> _openColumnFilter(String column, String label) async {
    final isNumeric = {'system', 'actual', 'diff'}.contains(column);
    final values =
        widget.rows
            .map((row) => _columnValue(row, column))
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) {
            if (isNumeric) {
              final av = num.tryParse(a.replaceAll(',', ''));
              final bv = num.tryParse(b.replaceAll(',', ''));
              if (av != null && bv != null) return av.compareTo(bv);
              if (av != null) return -1;
              if (bv != null) return 1;
            }
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
    final current = Set<String>.from(_columnFilters[column] ?? values);
    final result = await showDialog<_ColumnFilterResult>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => _ColumnFilterDialog(
        title: label,
        values: values,
        selected: current,
        sortAscending: _sortColumn == column ? _sortAscending : true,
        isNumeric: isNumeric,
        numericFilter: _numericFilters[column],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _sortColumn = column;
      _sortAscending = result.sortAscending;
      if (result.selected.length == values.length) {
        _columnFilters.remove(column);
      } else {
        _columnFilters[column] = result.selected;
      }
      if (result.numericFilter?.isValid == true) {
        _numericFilters[column] = result.numericFilter!;
      } else {
        _numericFilters.remove(column);
      }
      _rebuildIndexes();
    });
  }

  Future<void> _openNoteDialog(StockCheckTask row) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _StockCheckNoteDialog(row: row),
    );
    if (note == null || !mounted) return;
    try {
      await Supabase.instance.client
          .from('stock_check_tasks')
          .update({
            'note': note,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', row.id);
      final updated = row.copyWith(note: note);
      widget.onRowUpdated?.call(updated);
      setState(() {
        final index = _filteredRows.indexWhere((item) => item.id == row.id);
        if (index >= 0) _filteredRows[index] = updated;
        _rebuildIndexes();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save note: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }
}

class _StockCheckItem {
  final String itemCode;
  final String itemName;

  const _StockCheckItem({required this.itemCode, required this.itemName});
}

class _SearchableBranchFilter extends StatelessWidget {
  final Set<String> selectedBranches;
  final List<String> branches;
  final ValueChanged<Set<String>> onChanged;

  const _SearchableBranchFilter({
    required this.selectedBranches,
    required this.branches,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = selectedBranches.isEmpty
        ? 'All Branches'
        : selectedBranches.length == 1
        ? selectedBranches.first
        : '${selectedBranches.length} branches selected';
    return InkWell(
      onTap: () async {
        final selected = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _BranchFilterSearchDialog(
            branches: branches,
            selected: selectedBranches,
          ),
        );
        if (selected != null) onChanged(selected);
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _StockCheckResultTableState._filterDecoration('Branch'),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.search_rounded, color: AppColors.subText),
          ],
        ),
      ),
    );
  }
}

class _BranchFilterSearchDialog extends StatefulWidget {
  final List<String> branches;
  final Set<String> selected;

  const _BranchFilterSearchDialog({
    required this.branches,
    required this.selected,
  });

  @override
  State<_BranchFilterSearchDialog> createState() =>
      _BranchFilterSearchDialogState();
}

class _BranchFilterSearchDialogState extends State<_BranchFilterSearchDialog> {
  final _controller = TextEditingController();
  late final Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selected);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _search.trim().toLowerCase();
    final options = widget.branches
        .where(
          (branch) => needle.isEmpty || branch.toLowerCase().contains(needle),
        )
        .toList();
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 420,
        height: 520,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.store_rounded,
                    color: AppColors.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Select branches',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                decoration: _StockCheckResultTableState._filterDecoration(
                  'Search branch',
                  icon: Icons.search_rounded,
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _selected
                        ..clear()
                        ..addAll(widget.branches);
                    }),
                    child: const Text(
                      'Select all',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _selected.isEmpty
                        ? 'All branches'
                        : '${_selected.length} selected',
                    style: const TextStyle(
                      color: AppColors.subText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  itemCount: options.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final branch = options[index];
                    final selected = _selected.contains(branch);
                    return ListTile(
                      dense: true,
                      selected: selected,
                      selectedTileColor: AppColors.primaryColor.withValues(
                        alpha: .08,
                      ),
                      leading: Icon(
                        selected
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        color: selected
                            ? AppColors.primaryColor
                            : AppColors.subText,
                      ),
                      title: Text(
                        branch,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () => setState(() {
                        if (selected) {
                          _selected.remove(branch);
                        } else {
                          _selected.add(branch);
                        }
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockCheckNoteDialog extends StatefulWidget {
  final StockCheckTask row;

  const _StockCheckNoteDialog({required this.row});

  @override
  State<_StockCheckNoteDialog> createState() => _StockCheckNoteDialogState();
}

class _StockCheckNoteDialogState extends State<_StockCheckNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.row.note);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.backgroundWidget,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Stock check note',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.row.itemName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.row.branchName} - ${widget.row.itemCode}',
              style: const TextStyle(
                color: AppColors.subText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 7,
              decoration: _StockCheckResultTableState._filterDecoration(
                'Write note for this branch item',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          icon: const Icon(Icons.cloud_done_rounded),
          label: const Text('Save note'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
          ),
        ),
      ],
    );
  }
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

class _ColumnFilterResult {
  final Set<String> selected;
  final bool sortAscending;
  final _NumericColumnFilter? numericFilter;

  const _ColumnFilterResult({
    required this.selected,
    required this.sortAscending,
    this.numericFilter,
  });
}

class _NumericColumnFilter {
  final String mode;
  final num? first;
  final num? second;

  const _NumericColumnFilter({
    required this.mode,
    required this.first,
    required this.second,
  });

  bool get isValid {
    if (mode == 'none') return false;
    if (mode == 'between') return first != null && second != null;
    return first != null;
  }

  bool matches(num? value) {
    if (!isValid) return true;
    if (value == null) return false;
    return switch (mode) {
      'gt' => value > first!,
      'gte' => value >= first!,
      'lt' => value < first!,
      'lte' => value <= first!,
      'between' =>
        value >= math.min(first!.toDouble(), second!.toDouble()) &&
            value <= math.max(first!.toDouble(), second!.toDouble()),
      _ => true,
    };
  }
}

class _ColumnFilterDialog extends StatefulWidget {
  final String title;
  final List<String> values;
  final Set<String> selected;
  final bool sortAscending;
  final bool isNumeric;
  final _NumericColumnFilter? numericFilter;

  const _ColumnFilterDialog({
    required this.title,
    required this.values,
    required this.selected,
    required this.sortAscending,
    this.isNumeric = false,
    this.numericFilter,
  });

  @override
  State<_ColumnFilterDialog> createState() => _ColumnFilterDialogState();
}

class _ColumnFilterDialogState extends State<_ColumnFilterDialog> {
  late final TextEditingController _searchController;
  late final TextEditingController _firstNumberController;
  late final TextEditingController _secondNumberController;
  late Set<String> _selected;
  late bool _sortAscending;
  late String _numberMode;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _firstNumberController = TextEditingController(
      text: widget.numericFilter?.first?.toString() ?? '',
    );
    _secondNumberController = TextEditingController(
      text: widget.numericFilter?.second?.toString() ?? '',
    );
    _selected = Set<String>.from(widget.selected);
    _sortAscending = widget.sortAscending;
    _numberMode = widget.numericFilter?.mode ?? 'none';
  }

  @override
  void dispose() {
    _searchController.dispose();
    _firstNumberController.dispose();
    _secondNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.values.where((value) {
      return _search.trim().isEmpty ||
          value.toLowerCase().contains(_search.trim().toLowerCase());
    }).toList();
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: widget.isNumeric ? 430 : 390,
        height: widget.isNumeric ? 680 : 560,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.filter_alt_rounded,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _sortAscending = true),
                      icon: const Icon(
                        Icons.arrow_upward_rounded,
                        size: 18,
                        color: AppColors.secondaryColor,
                      ),
                      label: const Text(
                        'Sort Low to High',
                        style: TextStyle(color: AppColors.secondaryColor),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _sortAscending
                            ? const Color(0xFFEFF6FF)
                            : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _sortAscending = false),
                      icon: const Icon(
                        Icons.arrow_downward_rounded,
                        size: 18,
                        color: AppColors.secondaryColor,
                      ),
                      label: const Text(
                        'Sort High to Low',
                        style: TextStyle(color: AppColors.secondaryColor),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: !_sortAscending
                            ? const Color(0xFFEFF6FF)
                            : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.isNumeric) ...[
                const SizedBox(height: 12),
                _NumericFilterPanel(
                  mode: _numberMode,
                  firstController: _firstNumberController,
                  secondController: _secondNumberController,
                  onModeChanged: (value) {
                    setState(() => _numberMode = value);
                  },
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search values',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: AppColors.backgroundWidget,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primaryColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primaryColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primaryColor),
                  ),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selected = Set<String>.from(widget.values);
                      });
                    },
                    child: const Text(
                      'Select all',
                      style: TextStyle(color: AppColors.secondaryColor),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text(
                      'Clear',
                      style: TextStyle(color: AppColors.secondaryColor),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_selected.length} selected',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('No values'))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final value = visible[index];
                          return CheckboxListTile(
                            dense: true,
                            activeColor: AppColors.primaryColor,
                            value: _selected.contains(value),
                            title: Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selected.add(value);
                                } else {
                                  _selected.remove(value);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        _ColumnFilterResult(
                          selected: Set<String>.from(widget.values),
                          sortAscending: _sortAscending,
                          numericFilter: null,
                        ),
                      );
                    },
                    child: const Text(
                      'Clear filter',
                      style: TextStyle(color: AppColors.secondaryColor),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                    ),
                    onPressed: () {
                      Navigator.pop(
                        context,
                        _ColumnFilterResult(
                          selected: _selected,
                          sortAscending: _sortAscending,
                          numericFilter: _buildNumericFilter(),
                        ),
                      );
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _NumericColumnFilter? _buildNumericFilter() {
    if (!widget.isNumeric || _numberMode == 'none') return null;
    num? parse(TextEditingController controller) {
      final text = controller.text.trim().replaceAll(',', '');
      if (text.isEmpty) return null;
      return num.tryParse(text);
    }

    final filter = _NumericColumnFilter(
      mode: _numberMode,
      first: parse(_firstNumberController),
      second: parse(_secondNumberController),
    );
    return filter.isValid ? filter : null;
  }
}

class _NumericFilterPanel extends StatelessWidget {
  final String mode;
  final TextEditingController firstController;
  final TextEditingController secondController;
  final ValueChanged<String> onModeChanged;

  const _NumericFilterPanel({
    required this.mode,
    required this.firstController,
    required this.secondController,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showSecond = mode == 'between';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pin_rounded, color: AppColors.primaryColor, size: 18),
              SizedBox(width: 7),
              Text(
                'Number filter',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: mode,
            decoration: _StockCheckResultTableState._filterDecoration(
              'Condition',
            ),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('No number filter')),
              DropdownMenuItem(value: 'gt', child: Text('Greater than')),
              DropdownMenuItem(
                value: 'gte',
                child: Text('Greater than or equal'),
              ),
              DropdownMenuItem(value: 'lt', child: Text('Less than')),
              DropdownMenuItem(value: 'lte', child: Text('Less than or equal')),
              DropdownMenuItem(value: 'between', child: Text('Between')),
            ],
            onChanged: (value) => onModeChanged(value ?? 'none'),
          ),
          if (mode != 'none') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: firstController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: _StockCheckResultTableState._filterDecoration(
                      showSecond ? 'From' : 'Value',
                    ),
                  ),
                ),
                if (showSecond) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: secondController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: _StockCheckResultTableState._filterDecoration(
                        'To',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FastStockCheckResultsTable extends StatefulWidget {
  final List<StockCheckTask> rows;
  final bool showBarcodeSticker;
  final Set<String> activeFilters;
  final String sortColumn;
  final bool sortAscending;
  final void Function(String column, String label) onColumnFilter;
  final ValueChanged<StockCheckTask> onRowTap;

  const _FastStockCheckResultsTable({
    required this.rows,
    required this.showBarcodeSticker,
    required this.activeFilters,
    required this.sortColumn,
    required this.sortAscending,
    required this.onColumnFilter,
    required this.onRowTap,
  });

  @override
  State<_FastStockCheckResultsTable> createState() =>
      _FastStockCheckResultsTableState();
}

class _FastStockCheckResultsTableState
    extends State<_FastStockCheckResultsTable> {
  double _branchW = 150;
  double _codeW = 130;
  double _nameW = 520;
  double _qtyW = 95;
  double _diffW = 68;
  double _barcodeW = 220;
  double _submitterW = 180;
  double _employeeW = 150;
  double _noteW = 220;
  double _statusW = 200;

  double get _width =>
      _branchW +
      _codeW +
      _nameW +
      (_qtyW * 2) +
      _diffW +
      (widget.showBarcodeSticker ? _barcodeW : 0) +
      _submitterW +
      _employeeW +
      _noteW +
      _statusW;

  void _resize(String column, double delta) {
    setState(() {
      switch (column) {
        case 'branch':
          _branchW = (_branchW + delta).clamp(110, 360);
        case 'itemCode':
          _codeW = (_codeW + delta).clamp(110, 260);
        case 'itemName':
          _nameW = (_nameW + delta).clamp(260, 820);
        case 'system':
          _qtyW = (_qtyW + delta).clamp(82, 180);
        case 'diff':
          _diffW = (_diffW + delta).clamp(62, 150);
        case 'barcode':
          _barcodeW = (_barcodeW + delta).clamp(180, 360);
        case 'submittedByName':
          _submitterW = (_submitterW + delta).clamp(140, 320);
        case 'submittedByEmployeeId':
          _employeeW = (_employeeW + delta).clamp(120, 260);
        case 'note':
          _noteW = (_noteW + delta).clamp(150, 420);
        case 'status':
          _statusW = (_statusW + delta).clamp(130, 280);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Column(
        children: [
          _row(
            cells: [
              _header('Branch', 'branch', _branchW),
              _header('Item Code', 'itemCode', _codeW),
              _header('Item Name', 'itemName', _nameW),
              _header('System', 'system', _qtyW),
              _header('Actual', 'actual', _qtyW),
              _header('Diff', 'diff', _diffW),
              if (widget.showBarcodeSticker)
                _header('Barcode Sticker is Correct', 'barcode', _barcodeW),
              _header('Submitted By', 'submittedByName', _submitterW),
              _header('Employee ID', 'submittedByEmployeeId', _employeeW),
              _header('Note', 'note', _noteW),
              _header('Status', 'status', _statusW),
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
                itemCount: widget.rows.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFFD9E8F5)),
                itemBuilder: (context, index) {
                  final row = widget.rows[index];
                  return _row(
                    cells: [
                      _cell(row.branchName, _branchW),
                      _cell(row.itemCode, _codeW),
                      _itemNameCell(row),
                      _cell(row.systemQty?.toString() ?? '', _qtyW),
                      _cell(row.actualQty?.toString() ?? '', _qtyW),
                      _cell(row.variance?.toString() ?? '', _diffW),
                      if (widget.showBarcodeSticker)
                        _cell(
                          row.includeBarcodeStickerCheck
                              ? _StockCheckResultTableState._yesNo(
                                  row.barcodeStickerIsCorrect,
                                )
                              : '',
                          _barcodeW,
                        ),
                      _cell(row.submittedByName, _submitterW, maxLines: 2),
                      _cell(row.submittedByEmployeeId, _employeeW),
                      _noteCell(row),
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

  Widget _header(String text, String column, double width) {
    final filtered = widget.activeFilters.contains(column);
    final sorted = widget.sortColumn == column;
    return SizedBox(
      width: width,
      height: 48,
      child: Stack(
        children: [
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.only(left: 8, right: 34),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFFD9E8F5))),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Positioned(
            right: 14,
            top: 0,
            bottom: 0,
            child: Tooltip(
              message: 'Filter / sort',
              child: InkWell(
                onTap: () => widget.onColumnFilter(column, text),
                borderRadius: BorderRadius.circular(999),
                child: Icon(
                  filtered
                      ? Icons.filter_alt_rounded
                      : sorted
                      ? (widget.sortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded)
                      : Icons.filter_list_rounded,
                  size: 18,
                  color: filtered || sorted
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  _resize(column, details.delta.dx);
                },
                child: Container(
                  width: 10,
                  alignment: Alignment.center,
                  child: Container(width: 2, color: const Color(0xFFCBD5E1)),
                ),
              ),
            ),
          ),
        ],
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
      child: SelectableText(
        text,
        maxLines: maxLines,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _itemNameCell(StockCheckTask row) {
    return Container(
      width: _nameW,
      height: 54,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFD9E8F5))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              row.itemName,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: row.note.trim().isEmpty ? 'Add note' : 'Edit note',
            child: IconButton(
              onPressed: () => widget.onRowTap(row),
              icon: Icon(
                row.note.trim().isEmpty
                    ? Icons.note_add_outlined
                    : Icons.sticky_note_2_rounded,
                size: 18,
              ),
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                foregroundColor: AppColors.primaryColor,
                backgroundColor: AppColors.primaryColor.withValues(alpha: .08),
                minimumSize: const Size(32, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
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

  Widget _noteCell(StockCheckTask row) {
    final hasNote = row.note.trim().isNotEmpty;
    return Container(
      width: _noteW,
      height: 54,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFD9E8F5))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasNote ? Icons.sticky_note_2_rounded : Icons.add_comment_rounded,
            size: 17,
            color: hasNote ? AppColors.primaryColor : AppColors.subText,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: SelectableText(
              hasNote ? row.note : 'Add note',
              maxLines: 1,
              style: TextStyle(
                color: hasNote ? AppColors.secondaryColor : AppColors.subText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TablePanButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TablePanButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 42,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Icon(icon, color: const Color(0xFF2563EB), size: 24),
        ),
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

  _StockCheckBatch({required this.id, required this.rows});

  String get title => rows.isEmpty ? 'Stock Check' : rows.first.title;
  DateTime? get sentAt => rows.isEmpty ? null : rows.first.sentAt;
  DateTime? get expiresAt => rows.isEmpty ? null : rows.first.expiresAt;
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!.toLocal());
  int get total => rows.length;
  late final int submitted = rows.where((row) => row.isSubmitted).length;
  int get pending => total - submitted;
  late final int branches = rows.map((row) => row.branchName).toSet().length;
  late final int products = rows.map((row) => row.itemCode).toSet().length;
}

class _StockCheckRowStats {
  final int total;
  final int submitted;
  final int counted;
  final int correct;
  final int nonZero;

  const _StockCheckRowStats({
    required this.total,
    required this.submitted,
    required this.counted,
    required this.correct,
    required this.nonZero,
  });

  factory _StockCheckRowStats.fromRows(List<StockCheckTask> rows) {
    var submitted = 0;
    var counted = 0;
    var correct = 0;
    var nonZero = 0;
    for (final row in rows) {
      if (row.isSubmitted) submitted++;
      if (row.systemQty == null || row.actualQty == null) continue;
      counted++;
      if ((row.systemQty ?? 0) != 0 || (row.actualQty ?? 0) != 0) {
        nonZero++;
      }
      final diff = (row.variance ?? 0).toDouble().abs();
      if (diff <= _stockCheckAccuracyTolerance + 1e-9) correct++;
    }
    return _StockCheckRowStats(
      total: rows.length,
      submitted: submitted,
      counted: counted,
      correct: correct,
      nonZero: nonZero,
    );
  }
}

class _StockCheckAnalysisReport {
  final List<StockCheckTask> rows;
  late final _StockCheckRowStats _stats = _StockCheckRowStats.fromRows(rows);
  late final List<_StockCheckBranchAnalysis> branches = _buildBranches();
  late final List<_StockCheckComparisonRow> comparisonRows =
      _buildComparisonRows();

  _StockCheckAnalysisReport(this.rows);

  int get submitted => _stats.submitted;
  int get pending => rows.length - submitted;
  int get counted => _stats.counted;
  int get correct => _stats.correct;
  int get different => counted - correct;
  double get accuracyRate => counted == 0 ? 0 : correct * 100 / counted;
  double get completionRate => rows.isEmpty ? 0 : submitted * 100 / rows.length;
  int get riskyBranches => branches.where((row) => row.hasDeadlineRisk).length;
  int get notStartedBranches =>
      branches.where((row) => row.submitted == 0).length;
  int get completedBranches => branches.where((row) => row.pending == 0).length;
  int get below75Branches =>
      branches.where((row) => row.counted > 0 && row.accuracyRate < 75).length;
  int get nonZeroCounted => _stats.nonZero;

  List<_StockCheckBranchAnalysis> _buildBranches() {
    final byBranch = <String, List<StockCheckTask>>{};
    for (final row in rows) {
      byBranch.putIfAbsent(row.branchName.trim(), () => []).add(row);
    }
    final result = byBranch.entries
        .where((entry) => entry.key.isNotEmpty)
        .map((entry) => _StockCheckBranchAnalysis(entry.key, entry.value))
        .toList();
    result.sort((a, b) {
      if (a.hasDeadlineRisk != b.hasDeadlineRisk) {
        return a.hasDeadlineRisk ? -1 : 1;
      }
      final accuracy = a.accuracyRate.compareTo(b.accuracyRate);
      if (accuracy != 0) return accuracy;
      final completion = a.completionRate.compareTo(b.completionRate);
      if (completion != 0) return completion;
      return a.branch.toLowerCase().compareTo(b.branch.toLowerCase());
    });
    return result;
  }

  List<_StockCheckComparisonRow> _buildComparisonRows() {
    final batchIds = rows.map((row) => row.batchId).toSet();
    if (batchIds.length < 2) return const [];
    final byBatch = <String, List<StockCheckTask>>{};
    for (final row in rows) {
      byBatch.putIfAbsent(row.batchId, () => []).add(row);
    }
    final batches = byBatch.entries.toList()
      ..sort((a, b) {
        final ad =
            a.value.first.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd =
            b.value.first.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });
    final firstByBranch = _groupRowsByBranch(batches.first.value);
    final lastByBranch = _groupRowsByBranch(batches.last.value);
    final branches = {...firstByBranch.keys, ...lastByBranch.keys};

    final result = <_StockCheckComparisonRow>[];
    for (final branch in branches) {
      final firstBranchRows = firstByBranch[branch] ?? const <StockCheckTask>[];
      final lastBranchRows = lastByBranch[branch] ?? const <StockCheckTask>[];
      final first = _StockCheckBranchAnalysis(branch, firstBranchRows);
      final last = _StockCheckBranchAnalysis(branch, lastBranchRows);
      final firstByItem = {
        for (final row in firstBranchRows)
          row.itemCode.trim().toLowerCase(): row,
      };
      var common = 0;
      var improved = 0;
      var worsened = 0;
      for (final row in lastBranchRows) {
        final previous = firstByItem[row.itemCode.trim().toLowerCase()];
        if (previous == null || !_isCounted(previous) || !_isCounted(row)) {
          continue;
        }
        common++;
        final before = _effectiveAbsVariance(previous);
        final after = _effectiveAbsVariance(row);
        if (after < before) improved++;
        if (after > before) worsened++;
      }
      result.add(
        _StockCheckComparisonRow(
          branch: branch,
          firstAccuracy: first.accuracyRate,
          lastAccuracy: last.accuracyRate,
          commonItems: common,
          improved: improved,
          worsened: worsened,
        ),
      );
    }
    result.sort((a, b) => a.delta.compareTo(b.delta));
    return result;
  }

  static Map<String, List<StockCheckTask>> _groupRowsByBranch(
    List<StockCheckTask> rows,
  ) {
    final grouped = <String, List<StockCheckTask>>{};
    for (final row in rows) {
      final branch = row.branchName.trim();
      if (branch.isEmpty) continue;
      grouped.putIfAbsent(branch, () => []).add(row);
    }
    return grouped;
  }

  static bool _isCounted(StockCheckTask row) {
    if (row.systemQty == null || row.actualQty == null) return false;
    return true;
  }

  static double _effectiveAbsVariance(StockCheckTask row) {
    return (row.variance ?? 0).toDouble().abs();
  }
}

class _StockCheckBranchAnalysis {
  final String branch;
  final List<StockCheckTask> rows;
  late final _StockCheckRowStats _stats = _StockCheckRowStats.fromRows(rows);

  _StockCheckBranchAnalysis(this.branch, this.rows);

  int get total => _stats.total;
  int get submitted => _stats.submitted;
  int get pending => total - submitted;
  int get counted => _stats.counted;
  int get correct => _stats.correct;
  int get different => counted - correct;
  int get toleranceCorrect => correct;
  int get nonZeroCounted => _stats.nonZero;
  double get accuracyRate => counted == 0 ? 0 : correct * 100 / counted;
  double get completionRate => total == 0 ? 0 : submitted * 100 / total;
  late final bool hasDeadlineRisk = _computeDeadlineRisk();

  bool _computeDeadlineRisk() {
    if (pending == 0 || completionRate >= 50) return false;
    final now = DateTime.now();
    return rows.any((row) {
      final expiresAt = row.expiresAt?.toLocal();
      if (expiresAt == null || expiresAt.isBefore(now)) return false;
      return expiresAt.difference(now) <= const Duration(days: 2);
    });
  }
}

class _StockCheckComparisonRow {
  final String branch;
  final double firstAccuracy;
  final double lastAccuracy;
  final int commonItems;
  final int improved;
  final int worsened;

  const _StockCheckComparisonRow({
    required this.branch,
    required this.firstAccuracy,
    required this.lastAccuracy,
    required this.commonItems,
    required this.improved,
    required this.worsened,
  });

  double get delta => lastAccuracy - firstAccuracy;
}

class _StockCheckTopTabs extends StatelessWidget {
  final bool analysis;
  final ValueChanged<bool> onChanged;

  const _StockCheckTopTabs({required this.analysis, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeButton(
              selected: !analysis,
              icon: Icons.inventory_2_rounded,
              label: 'Stock Checks',
              onTap: () => onChanged(false),
            ),
            const SizedBox(width: 18),
            _ModeButton(
              selected: analysis,
              icon: Icons.analytics_rounded,
              label: 'Accuracy Analysis',
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.primaryColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? AppColors.primaryColor : AppColors.subText,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primaryColor : AppColors.subText,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisBatchPickerDialog extends StatefulWidget {
  final List<_StockCheckBatch> batches;
  final Set<String> selectedBatchIds;

  const _AnalysisBatchPickerDialog({
    required this.batches,
    required this.selectedBatchIds,
  });

  @override
  State<_AnalysisBatchPickerDialog> createState() =>
      _AnalysisBatchPickerDialogState();
}

class _AnalysisBatchPickerDialogState
    extends State<_AnalysisBatchPickerDialog> {
  late final _selected = {...widget.selectedBatchIds};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.backgroundWidget,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.compare_arrows_rounded,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Choose projects for analysis',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 430,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select one project for branch accuracy, or multiple projects to compare accuracy changes for the same branch and repeated items.',
              style: TextStyle(
                color: AppColors.subText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: widget.batches.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final batch = widget.batches[index];
                  final selected = _selected.contains(batch.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selected.add(batch.id);
                        } else {
                          _selected.remove(batch.id);
                        }
                      });
                    },
                    title: Text(
                      batch.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      '${batch.branches} branches • ${batch.products} products • ${batch.submitted}/${batch.total} submitted',
                    ),
                    activeColor: AppColors.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: selected
                        ? AppColors.primaryColor.withValues(alpha: .08)
                        : const Color(0xFFF8FAFC),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
          ),
          child: Text('Apply ${_selected.length} project(s)'),
        ),
      ],
    );
  }
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

class _SentSourceToggle extends StatelessWidget {
  final String value;
  final int inventoryCount;
  final int storeCount;
  final ValueChanged<String> onChanged;

  const _SentSourceToggle({
    required this.value,
    required this.inventoryCount,
    required this.storeCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E8F5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SentSourceTab(
              selected: value == 'inventory',
              icon: Icons.inventory_2_rounded,
              label: 'Inventory',
              count: inventoryCount,
              color: const Color(0xFF2563EB),
              onTap: () => onChanged('inventory'),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SentSourceTab(
              selected: value == 'store',
              icon: Icons.storefront_rounded,
              label: 'Store',
              count: storeCount,
              color: const Color(0xFF059669),
              onTap: () => onChanged('store'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SentSourceTab extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _SentSourceTab({
    required this.selected,
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: selected
                ? Border.all(color: color.withValues(alpha: .28))
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: .10),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? color : const Color(0xFF64748B),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? color : const Color(0xFF475569),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? color.withValues(alpha: .12) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: selected ? color : const Color(0xFF64748B),
                    fontSize: 11,
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
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.secondaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
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
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEditDeadline;
  final VoidCallback onDelete;

  const _StockCheckBatchCard({
    required this.batch,
    required this.selected,
    required this.deleting,
    required this.canManage,
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
                  if (canManage) ...[
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
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
