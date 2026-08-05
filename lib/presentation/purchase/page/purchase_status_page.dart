import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/purchase_status_excel_exporter.dart';
import '../../../core/utils/purchase_status_excel_importer.dart';
import '../../../data/datasources/remote/purchase_status_remote_ds.dart';
import '../../../domain/entities/purchase_status_record.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../widgets/purchase_status_grid.dart';

class PurchaseStatusPage extends StatefulWidget {
  const PurchaseStatusPage({super.key});

  @override
  State<PurchaseStatusPage> createState() => _PurchaseStatusPageState();
}

class _PurchaseStatusPageState extends State<PurchaseStatusPage> {
  late final PurchaseStatusRemoteDs _remote;
  final _searchController = TextEditingController();
  final _gridController = PurchaseStatusGridController();
  Timer? _searchDebounce;
  List<PurchaseStatusRecord> _records = const [];
  List<PurchaseStatusRecord> _visibleRecords = const [];
  Map<int, String> _searchIndex = const {};
  List<PurchaseStatusOption> _statuses = const [];
  int? _statusFilter;
  String _workflowFilter = 'pending';
  bool _loading = true;
  bool _exporting = false;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _remote = PurchaseStatusRemoteDs(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _setRecords(List<PurchaseStatusRecord> records) {
    _records = records;
    _searchIndex = {
      for (final record in records)
        record.id: [
          record.itemCode,
          record.itemName,
          record.statusName,
          record.alternativeItemCode,
          record.alternativeItemName,
          record.purchaseStatus,
          record.category,
          record.supplier,
          record.note,
          record.workflowStatus,
          record.reviewOrigin,
        ].join('\u0000').toLowerCase(),
    };
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty && _statusFilter == null && _workflowFilter == 'all') {
      _visibleRecords = _records;
      return;
    }
    _visibleRecords = _records
        .where((record) {
          if (_statusFilter != null && record.statusId != _statusFilter) {
            return false;
          }
          if (_workflowFilter != 'all' &&
              record.workflowStatus != _workflowFilter) {
            return false;
          }
          return query.isEmpty ||
              (_searchIndex[record.id]?.contains(query) ?? false);
        })
        .toList(growable: false);
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      setState(_applyFilters);
    });
  }

  void _changeStatusFilter(int? value) {
    setState(() {
      _statusFilter = value;
      _applyFilters();
    });
  }

  void _changeWorkflowFilter(String? value) {
    if (value == null) return;
    setState(() {
      _workflowFilter = value;
      _applyFilters();
    });
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _gridController.clearFilters();
    setState(() {
      _statusFilter = null;
      _workflowFilter = 'pending';
      _applyFilters();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _remote.fetchRecords(),
        _remote.fetchStatuses(),
      ]).timeout(const Duration(seconds: 25));
      if (!mounted) return;
      setState(() {
        _setRecords(result[0] as List<PurchaseStatusRecord>);
        _statuses = result[1] as List<PurchaseStatusOption>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([PurchaseStatusRecord? record]) async {
    final purchaseTheme = _purchaseThemeData(Theme.of(context));
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Theme(
        data: purchaseTheme,
        child: _PurchaseRecordDialog(
          remote: _remote,
          statuses: _statuses,
          initialRecord: record,
          onStatusAdded: (status) {
            setState(() => _statuses = [..._statuses, status]);
          },
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(PurchaseStatusRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete purchase status?'),
        content: Text(
          '${record.itemCode} — ${record.itemName}\n\nThe old record will remain safely available in the history log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _remote.delete(record.id);
      if (!mounted) return;
      setState(() {
        _setRecords(
          _records.where((row) => row.id != record.id).toList(growable: false),
        );
      });
      _showMessage('Record deleted and archived in the log.');
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), isError: true);
    }
  }

  Future<void> _showHistory(PurchaseStatusRecord record) async {
    showDialog<void>(
      context: context,
      builder: (_) => _HistoryDialog(remote: _remote, record: record),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Colors.red.shade700
            : AppColors.secondaryColor,
      ),
    );
  }

  Future<void> _exportVisibleRecords() async {
    if (_exporting) return;
    final records = _gridController.visibleRecords;
    if (records.isEmpty) {
      _showMessage('There are no visible records to export.', isError: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      await PurchaseStatusExcelExporter.export(records, _statuses);
      if (mounted) {
        _showMessage(
          '${records.length} visible records exported successfully.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importExcel() async {
    if (_importing) return;
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
      allowMultiple: false,
    );
    if (selection == null || !mounted) return;
    final file = selection.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      await _showImportFailure(
        file.name,
        const PurchaseStatusImportFailure(
          title: 'Could not open the selected file',
          summary: 'The browser could not read the Excel file.',
          issues: [
            PurchaseStatusImportIssue(
              field: 'File',
              message: 'No file data was received from the browser.',
              hint: 'Close the workbook in Excel, select it again, and retry.',
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _importing = true);
    PurchaseStatusExcelImportPreview? preview;
    try {
      await Future<void>.delayed(Duration.zero);
      final parsedPreview = PurchaseStatusExcelImporter.parse(bytes, _statuses);
      preview = parsedPreview;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExcelImportPreviewDialog(
          fileName: file.name,
          preview: parsedPreview,
        ),
      );
      if (confirmed != true || !mounted) return;

      final result = await _remote.importExcelRows(
        parsedPreview.rows.map((row) => row.toJson()).toList(growable: false),
      );
      await _load();
      if (!mounted) return;
      final updated = result['updated'] ?? parsedPreview.rows.length;
      final addedStatuses = result['new_statuses'] ?? 0;
      _showMessage(
        '$updated products updated successfully. '
        '$addedStatuses new statuses added.',
      );
    } catch (error) {
      if (mounted) {
        await _showImportFailure(file.name, _mapImportFailure(error, preview));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showImportFailure(
    String fileName,
    PurchaseStatusImportFailure failure,
  ) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ExcelImportErrorDialog(fileName: fileName, failure: failure),
    );
  }

  PurchaseStatusImportFailure _mapImportFailure(
    Object error,
    PurchaseStatusExcelImportPreview? preview,
  ) {
    if (error is PurchaseStatusImportFailure) return error;

    if (error is PostgrestException) {
      final code = error.code;
      final message = error.message;
      final structuredMismatch = message == 'PURCHASE_STATUS_ITEM_NAME_MISMATCH'
          ? _purchaseStatusMismatchDetails(error.details)
          : null;
      if (structuredMismatch != null) {
        final recordId = _asInt(structuredMismatch['record_id']);
        PurchaseStatusExcelImportRow? sourceRow;
        if (recordId != null && preview != null) {
          for (final row in preview.rows) {
            if (row.recordId == recordId) {
              sourceRow = row;
              break;
            }
          }
        }
        final field = structuredMismatch['field']?.toString() ?? 'Item Name';
        final systemValue =
            structuredMismatch['system_value']?.toString() ?? '';
        final excelValue = structuredMismatch['excel_value']?.toString() ?? '';
        return PurchaseStatusImportFailure(
          title: 'Product name does not match',
          summary: sourceRow == null
              ? 'The product name in Excel is different from the current system record.'
              : 'Excel row ${sourceRow.excelRow} has a different product name from the current system record.',
          issues: [
            PurchaseStatusImportIssue(
              excelRow: sourceRow?.excelRow,
              field: field,
              message:
                  'System value: "${systemValue.isEmpty ? '(empty)' : systemValue}"\n'
                  'Excel value: "${excelValue.isEmpty ? '(empty)' : excelValue}"',
              hint:
                  'Restore the Item Name shown in the system, or export a fresh workbook. '
                  'Review Status may be different and does not block the import.',
            ),
          ],
          technicalCode: code,
        );
      }
      final identityMatch = RegExp(
        r'Item identity mismatch for record\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(message);
      if (identityMatch != null) {
        final recordId = int.tryParse(identityMatch.group(1)!);
        PurchaseStatusExcelImportRow? sourceRow;
        if (recordId != null && preview != null) {
          for (final row in preview.rows) {
            if (row.recordId == recordId) {
              sourceRow = row;
              break;
            }
          }
        }
        final itemLabel = sourceRow == null
            ? 'The product linked to record $recordId'
            : '${sourceRow.itemCode.isEmpty ? 'No item code' : sourceRow.itemCode} - '
                  '${sourceRow.itemName}';
        return PurchaseStatusImportFailure(
          title: 'Product identity does not match',
          summary: sourceRow == null
              ? 'A protected product value no longer matches the current Purchase Status record.'
              : 'Excel row ${sourceRow.excelRow} contains product details that no longer match the current record.',
          issues: [
            PurchaseStatusImportIssue(
              excelRow: sourceRow?.excelRow,
              field: 'Item Name',
              message:
                  '$itemLabel does not match the protected record identity.',
              hint:
                  'Export a fresh Purchase Status workbook and edit only '
                  'Status, Status Date, Alternative Item, and Note. Review '
                  'Status may change and is not validated. Do not change Item '
                  'Name or hidden columns.',
            ),
          ],
          technicalCode: code,
        );
      }

      if (code == '23505' || message.toLowerCase().contains('duplicate')) {
        return PurchaseStatusImportFailure(
          title: 'Duplicate product data',
          summary:
              'The workbook contains a product that would be saved more than once.',
          issues: const [
            PurchaseStatusImportIssue(
              field: 'Duplicate record',
              message: 'Two rows refer to the same Purchase Status record.',
              hint: 'Keep only one row for each product, then import again.',
            ),
          ],
          technicalCode: code,
        );
      }
      if (code == '23503' ||
          message.toLowerCase().contains('record not found')) {
        return PurchaseStatusImportFailure(
          title: 'Workbook is out of date',
          summary:
              'One or more products in this workbook no longer exist in Purchase Status.',
          issues: const [
            PurchaseStatusImportIssue(
              field: 'Product record',
              message: 'The workbook refers to an old or deleted record.',
              hint:
                  'Export a fresh workbook from Purchase Status and apply your changes there.',
            ),
          ],
          technicalCode: code,
        );
      }
      if (code == '23502') {
        final column = RegExp(
          r'column\s+"([^"]+)"',
          caseSensitive: false,
        ).firstMatch(message)?.group(1);
        return PurchaseStatusImportFailure(
          title: 'A required value is missing',
          summary:
              'The import could not save a required Purchase Status value.',
          issues: [
            PurchaseStatusImportIssue(
              field: column ?? 'Required field',
              message: 'A required value is empty.',
              hint:
                  'Export a fresh workbook and make sure the Status and Status Date are filled for every changed row.',
            ),
          ],
          technicalCode: code,
        );
      }
      if (code == '22P02' || code == '22007' || code == '22008') {
        return PurchaseStatusImportFailure(
          title: 'Invalid value format',
          summary:
              'A date, number, or protected identifier has an invalid format.',
          issues: const [
            PurchaseStatusImportIssue(
              field: 'Cell value',
              message:
                  'At least one changed cell cannot be converted to the expected format.',
              hint:
                  'Use DD/MM/YYYY for dates and do not edit hidden system columns.',
            ),
          ],
          technicalCode: code,
        );
      }
      if (code == '42501') {
        return PurchaseStatusImportFailure(
          title: 'Import permission is unavailable',
          summary:
              'Your account is not allowed to update Purchase Status from Excel.',
          contactSupport: true,
          technicalCode: code,
        );
      }
      if (code == '57014') {
        return PurchaseStatusImportFailure(
          title: 'Import took too long',
          summary: 'The server stopped the import before it finished.',
          issues: const [
            PurchaseStatusImportIssue(
              field: 'Import size',
              message:
                  'The workbook or current server load made processing exceed the allowed time.',
              hint:
                  'Retry once. If it happens again, export a fresh workbook or contact support.',
            ),
          ],
          contactSupport: true,
          technicalCode: code,
        );
      }
      if ({'PGRST202', 'PGRST205', '42883', '42P01', '42703'}.contains(code)) {
        return PurchaseStatusImportFailure(
          title: 'Purchase Status import is not configured',
          summary: 'A required database component is unavailable.',
          contactSupport: true,
          technicalCode: code,
        );
      }
      if (code == 'P0001') {
        return PurchaseStatusImportFailure(
          title: 'The workbook could not be validated',
          summary:
              'A protected Purchase Status rule rejected one of the changed rows.',
          issues: const [
            PurchaseStatusImportIssue(
              field: 'Changed row',
              message: 'The row does not match the latest product data.',
              hint:
                  'Export a fresh workbook, repeat the change, and import it again.',
            ),
          ],
          technicalCode: code,
        );
      }
      return PurchaseStatusImportFailure(
        title: 'The import could not be completed',
        summary:
            'The server could not process this workbook. No records were changed.',
        contactSupport: true,
        technicalCode: code,
      );
    }

    final text = error.toString().toLowerCase();
    if (error is TimeoutException || text.contains('timeout')) {
      return const PurchaseStatusImportFailure(
        title: 'Connection timed out',
        summary:
            'The import did not reach the server in time. No records were changed.',
        issues: [
          PurchaseStatusImportIssue(
            field: 'Connection',
            message: 'The server response took too long.',
            hint: 'Check the internet connection and retry the import.',
          ),
        ],
      );
    }
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('failed to fetch')) {
      return const PurchaseStatusImportFailure(
        title: 'Could not connect to the server',
        summary:
            'The workbook was validated, but the server could not be reached.',
        issues: [
          PurchaseStatusImportIssue(
            field: 'Connection',
            message: 'The network connection was interrupted.',
            hint:
                'Check the internet connection, then retry. The file does not need to be edited.',
          ),
        ],
      );
    }
    return const PurchaseStatusImportFailure(
      title: 'Unexpected import problem',
      summary: 'The import stopped safely and no records were changed.',
      contactSupport: true,
    );
  }

  Map<String, dynamic>? _purchaseStatusMismatchDetails(Object? details) {
    if (details is Map) {
      return details.map((key, value) => MapEntry(key.toString(), value));
    }
    final raw = details?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _visibleRecords;
    final pendingCount = _records.where((record) => record.isPending).length;
    final completeCount = _records.length - pendingCount;
    final purchaseTheme = _purchaseThemeData(Theme.of(context));

    return Theme(
      data: purchaseTheme,
      child: Scaffold(
        backgroundColor: const Color(0xfff4f7fb),
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                onAdd: () => _openEditor(),
                onRefresh: _load,
                onExport: _exportVisibleRecords,
                onImport: _importExcel,
                isExporting: _exporting,
                isImporting: _importing,
                canExport: !_loading && filtered.isNotEmpty,
                onLogout: () =>
                    context.read<AuthBloc>().add(AuthLogoutRequested()),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              label: 'Tracked items',
                              value: '${_records.length}',
                              icon: Icons.inventory_2_outlined,
                              color: AppColors.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _MetricCard(
                              label: 'Pending review',
                              value: '$pendingCount',
                              icon: Icons.pending_actions_rounded,
                              color: const Color(0xffe29220),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _MetricCard(
                              label: 'Completed',
                              value: '$completeCount',
                              icon: Icons.task_alt_rounded,
                              color: const Color(0xff0f9f7f),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _MetricCard(
                              label: 'Visible results',
                              value: '${filtered.length}',
                              icon: Icons.filter_alt_outlined,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xffe5eaf1)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0d17324d),
                                blurRadius: 24,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _Filters(
                                searchController: _searchController,
                                statuses: _statuses,
                                selectedStatus: _statusFilter,
                                selectedWorkflow: _workflowFilter,
                                onSearch: _scheduleSearch,
                                onStatusChanged: _changeStatusFilter,
                                onWorkflowChanged: _changeWorkflowFilter,
                                onClearFilters: _clearFilters,
                              ),
                              const Divider(
                                height: 1,
                                color: Color(0xffedf0f5),
                              ),
                              Expanded(child: _buildContent(filtered)),
                            ],
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
    );
  }

  Widget _buildContent(List<PurchaseStatusRecord> records) {
    if (_loading) return const _PurchaseLoadingState();
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load Purchase Status',
        message: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (records.isEmpty) {
      return _EmptyState(
        icon: Icons.playlist_add_rounded,
        title: _records.isEmpty
            ? 'Start your Purchase Status list'
            : 'No matching items',
        message: _records.isEmpty
            ? 'Add the first item. Product details will be completed automatically.'
            : 'Try changing the search text or status filter.',
        actionLabel: _records.isEmpty ? 'Add new status' : null,
        onAction: _records.isEmpty ? () => _openEditor() : null,
      );
    }
    return PurchaseStatusGrid(
      controller: _gridController,
      records: records,
      onEdit: _openEditor,
      onHistory: _showHistory,
      onDelete: _delete,
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onRefresh;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final bool isExporting;
  final bool isImporting;
  final bool canExport;
  final VoidCallback onLogout;

  const _TopBar({
    required this.onAdd,
    required this.onRefresh,
    required this.onExport,
    required this.onImport,
    required this.isExporting,
    required this.isImporting,
    required this.canExport,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff102d42), Color(0xff174d68)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x26102d42),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.shopping_cart_checkout_rounded,
              color: Color(0xff77d4ff),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Purchase Status',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Track availability, alternatives and supplier status',
                style: TextStyle(color: Color(0xffbad0dc), fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primaryColor.withValues(
                alpha: .5,
              ),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            onPressed: canExport && !isExporting ? onExport : null,
            icon: isExporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_download_outlined),
            label: Text(
              isExporting ? 'Exporting...' : 'Export Excel',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primaryColor.withValues(
                alpha: .5,
              ),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            onPressed: !isImporting && !isExporting ? onImport : null,
            icon: isImporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_upload_outlined),
            label: Text(
              isImporting ? 'Importing...' : 'Import Excel',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Add new status',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Sign out',
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, color: Color(0xffbad0dc)),
          ),
        ],
      ),
    );
  }
}

class _AnimatedExportButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const _AnimatedExportButton({
    required this.onPressed,
    required this.isLoading,
  });

  @override
  State<_AnimatedExportButton> createState() => _AnimatedExportButtonState();
}

class _AnimatedExportButtonState extends State<_AnimatedExportButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final scale = _pressed ? .97 : (_hovered && enabled ? 1.035 : 1.0);

    return Tooltip(
      message: 'Export visible rows to Excel',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: enabled
                    ? [AppColors.primaryColor, const Color(0xff238fc4)]
                    : [const Color(0xff688292), const Color(0xff58717f)],
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withValues(alpha: .38)),
              boxShadow: _hovered && enabled
                  ? [
                      BoxShadow(
                        color: AppColors.primaryColor.withValues(alpha: .38),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : const [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: enabled ? widget.onPressed : null,
                onHighlightChanged: (value) {
                  if (_pressed != value) setState(() => _pressed = value);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: widget.isLoading
                        ? const SizedBox(
                            key: ValueKey('export-loading'),
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.3,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            key: ValueKey('export-ready'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.file_download_outlined,
                                color: Colors.white,
                                size: 21,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Export Excel',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffe7ebf1)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.subText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PurchaseLoadingState extends StatelessWidget {
  const _PurchaseLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 46,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Loading purchase status...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Fetching records securely. This should only take a moment.',
            style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ExcelImportErrorDialog extends StatelessWidget {
  final String fileName;
  final PurchaseStatusImportFailure failure;

  const _ExcelImportErrorDialog({
    required this.fileName,
    required this.failure,
  });

  @override
  Widget build(BuildContext context) {
    final visibleIssues = failure.issues.take(50).toList(growable: false);
    final hiddenIssues = failure.issues.length - visibleIssues.length;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SelectionArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 14, 20),
                color: AppColors.secondaryColor,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            failure.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Excel import needs attention',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .72),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.secondaryColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        failure.summary,
                        style: TextStyle(
                          color: Colors.blueGrey.shade700,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _ImportSafetyNotice(),
                      if (visibleIssues.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          '${failure.issues.length} issue${failure.issues.length == 1 ? '' : 's'} found',
                          style: const TextStyle(
                            color: AppColors.secondaryColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...visibleIssues.map(_ImportIssueCard.new),
                        if (hiddenIssues > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '$hiddenIssues more issues are not shown. Fix the visible rows first, then import again.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                      if (failure.contactSupport) ...[
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor.withValues(
                              alpha: .08,
                            ),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: AppColors.primaryColor.withValues(
                                alpha: .3,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.support_agent_rounded,
                                color: AppColors.primaryColor,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'This issue is not caused by the Excel data. Please contact the support team${failure.technicalCode == null ? '.' : ' and provide reference code ${failure.technicalCode}.'}',
                                  style: const TextStyle(
                                    color: AppColors.secondaryColor,
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xfff8fafc),
                  border: Border(top: BorderSide(color: Color(0xffe5eaf0))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: Text(
                        failure.contactSupport && failure.issues.isEmpty
                            ? 'Close'
                            : 'Close and fix file',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportSafetyNotice extends StatelessWidget {
  const _ImportSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffecfdf5),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xffa7f3d0)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: Color(0xff07875f)),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'No records were changed. Correct the listed issues and upload the workbook again.',
              style: TextStyle(
                color: Color(0xff07664b),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportIssueCard extends StatelessWidget {
  final PurchaseStatusImportIssue issue;

  const _ImportIssueCard(this.issue);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xfffff8f7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffffcdc7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 54),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xffffe4e0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              issue.excelRow == null ? 'FILE' : 'ROW ${issue.excelRow}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xffb42318),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.field,
                  style: const TextStyle(
                    color: AppColors.secondaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(issue.message, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 17,
                      color: AppColors.primaryColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        issue.hint,
                        style: const TextStyle(
                          color: AppColors.secondaryColor,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
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

class _ExcelImportPreviewDialog extends StatelessWidget {
  final String fileName;
  final PurchaseStatusExcelImportPreview preview;

  const _ExcelImportPreviewDialog({
    required this.fileName,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 18, 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff102d42), Color(0xff174d68)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: const Row(
          children: [
            Icon(Icons.upload_file_rounded, color: Colors.white),
            SizedBox(width: 12),
            Text(
              'Confirm Excel import',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ImportFact(
                    label: 'Products to update',
                    value: '${preview.rows.length}',
                    icon: Icons.inventory_2_outlined,
                    color: AppColors.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ImportFact(
                    label: 'Total exported products',
                    value: '${preview.totalRows}',
                    icon: Icons.list_alt_rounded,
                    color: AppColors.secondaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${preview.rows.length} product${preview.rows.length == 1 ? '' : 's'} '
              'will be updated out of ${preview.totalRows}.',
              style: const TextStyle(
                color: AppColors.secondaryColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (preview.newStatuses.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'New statuses to add',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: preview.newStatuses
                    .map(
                      (status) => Chip(
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        label: Text(status),
                        backgroundColor: AppColors.primaryColor.withValues(
                          alpha: .1,
                        ),
                        side: BorderSide(
                          color: AppColors.primaryColor.withValues(alpha: .25),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xffeef7fc),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xffcbe6f4)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.primaryColor,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Only rows changed after export will be imported. '
                      'Unchanged rows are ignored. '
                      'The operation is atomic: if any row fails, nothing is changed.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: preview.rows.isEmpty
              ? null
              : () => Navigator.pop(context, true),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Import updates'),
        ),
      ],
    );
  }
}

class _ImportFact extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ImportFact({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final TextEditingController searchController;
  final List<PurchaseStatusOption> statuses;
  final int? selectedStatus;
  final String selectedWorkflow;
  final VoidCallback onSearch;
  final ValueChanged<int?> onStatusChanged;
  final ValueChanged<String?> onWorkflowChanged;
  final VoidCallback onClearFilters;

  const _Filters({
    required this.searchController,
    required this.statuses,
    required this.selectedStatus,
    required this.selectedWorkflow,
    required this.onSearch,
    required this.onStatusChanged,
    required this.onWorkflowChanged,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              onChanged: (_) => onSearch(),
              decoration: _inputDecoration(
                'Search by item, code, supplier, note...',
                Icons.search_rounded,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 245.w,
            child: DropdownButtonFormField<String>(
              key: ValueKey('workflow-$selectedWorkflow'),
              isExpanded: true,
              initialValue: selectedWorkflow,
              decoration: _inputDecoration(
                'Review queue',
                Icons.fact_check_outlined,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'pending',
                  child: Text('Pending review'),
                ),
                DropdownMenuItem(value: 'complete', child: Text('Completed')),
                DropdownMenuItem(value: 'all', child: Text('All products')),
              ],
              onChanged: onWorkflowChanged,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 320.w,
            child: DropdownButtonFormField<int?>(
              key: ValueKey('status-${selectedStatus ?? 'all'}'),
              isExpanded: true,
              initialValue: selectedStatus,
              decoration: _inputDecoration(
                'Filter by status',
                Icons.filter_list_rounded,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All statuses'),
                ),
                ...statuses.map(
                  (status) => DropdownMenuItem<int?>(
                    value: status.id,
                    child: Text(status.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: onStatusChanged,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 19),
              label: const Text('Clear filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 19),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseRecordDialog extends StatefulWidget {
  final PurchaseStatusRemoteDs remote;
  final List<PurchaseStatusOption> statuses;
  final PurchaseStatusRecord? initialRecord;
  final ValueChanged<PurchaseStatusOption> onStatusAdded;

  const _PurchaseRecordDialog({
    required this.remote,
    required this.statuses,
    required this.initialRecord,
    required this.onStatusAdded,
  });

  @override
  State<_PurchaseRecordDialog> createState() => _PurchaseRecordDialogState();
}

class _PurchaseRecordDialogState extends State<_PurchaseRecordDialog> {
  late List<PurchaseStatusOption> _statuses;
  final _note = TextEditingController();
  final _itemCode = TextEditingController();
  final _itemName = TextEditingController();
  final _altCode = TextEditingController();
  final _altName = TextEditingController();
  final _customStatus = TextEditingController();
  PurchaseProductSuggestion? _product;
  PurchaseProductSuggestion? _alternative;
  int? _statusId;
  int? _initialStatusId;
  late DateTime _date;
  int? _editingId;
  bool _saving = false;
  bool _addingCustomStatus = false;
  bool _savingCustomStatus = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _statuses = [...widget.statuses];
    _date = DateTime.now();
    _loadRecord(widget.initialRecord);
  }

  void _loadRecord(PurchaseStatusRecord? record) {
    if (record == null) return;
    _editingId = record.id;
    _itemCode.text = record.itemCode;
    _itemName.text = record.itemName;
    _altCode.text = record.alternativeItemCode;
    _altName.text = record.alternativeItemName;
    _note.text = record.note;
    _statusId = record.statusId;
    _initialStatusId = record.statusId;
    _date = record.isPending && record.wasAlreadyExisting
        ? DateTime.now()
        : record.statusDate ?? DateTime.now();
    _product = PurchaseProductSuggestion(
      itemCode: record.itemCode,
      itemName: record.itemName,
      purchaseStatus: record.purchaseStatus,
      category: record.category,
      supplier: record.supplier,
    );
    if (record.alternativeItemCode.isNotEmpty) {
      _alternative = PurchaseProductSuggestion(
        itemCode: record.alternativeItemCode,
        itemName: record.alternativeItemName,
        purchaseStatus: '',
        category: '',
        supplier: '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _note,
      _itemCode,
      _itemName,
      _altCode,
      _altName,
      _customStatus,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<PurchaseStatusRecord?> _checkExistingProduct(
    String itemCode,
    String itemName,
  ) async {
    try {
      return await widget.remote.findExisting(itemCode, itemName: itemName);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              'Product selected, but the duplicate check failed: ${_friendlyError(error)}';
        });
      }
      return null;
    }
  }

  Future<void> _selectProduct(PurchaseProductSuggestion product) async {
    // Fill both fields immediately. The duplicate check is remote and must not
    // make a successful suggestion click look unresponsive.
    setState(() {
      _product = product;
      _itemCode.text = product.itemCode;
      _itemName.text = product.itemName;
      _error = null;
    });

    final existing = await _checkExistingProduct(
      product.itemCode,
      product.itemName,
    );
    if (!mounted) return;
    if (existing != null && existing.id != _editingId) {
      final edit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primaryColor,
            size: 34,
          ),
          title: const Text('Item already exists'),
          content: Text(
            '${existing.itemCode} — ${existing.itemName}\n\nWould you like to open its current information and edit it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, edit it'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (edit == true) {
        setState(() => _loadRecord(existing));
      } else {
        _itemCode.clear();
        _itemName.clear();
        setState(() => _product = null);
      }
      return;
    }
  }

  Future<void> _addStatus() async {
    final name = _customStatus.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter the new status name.');
      return;
    }
    setState(() {
      _savingCustomStatus = true;
      _error = null;
    });
    try {
      final status = await widget.remote.addStatus(name);
      if (!mounted) return;
      setState(() {
        _statuses = [..._statuses, status];
        _statusId = status.id;
        _addingCustomStatus = false;
        _savingCustomStatus = false;
        _customStatus.clear();
      });
      widget.onStatusAdded(status);
    } catch (error) {
      if (mounted) {
        setState(() {
          _savingCustomStatus = false;
          _error = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (result != null) setState(() => _date = result);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    var product = _product;
    if (product == null) {
      final itemCode = _itemCode.text.trim();
      final itemName = _itemName.text.trim();
      if (itemName.isEmpty) {
        setState(() => _error = 'Item name is required.');
        return;
      }

      if (itemCode.isNotEmpty) {
        product = await widget.remote.resolveProduct(itemCode);
      } else {
        product = await widget.remote.resolveProduct(itemName);
      }

      product ??= PurchaseProductSuggestion(
        itemCode: itemCode,
        itemName: itemName,
        purchaseStatus: '',
        category: '',
        supplier: '',
      );
    }
    if (!mounted) return;
    if (_statusId == null) {
      setState(() => _error = 'Status is required.');
      return;
    }
    PurchaseProductSuggestion? alternative = _alternative;
    if (alternative == null &&
        (_altCode.text.trim().isNotEmpty || _altName.text.trim().isNotEmpty)) {
      alternative = await widget.remote.resolveProduct(
        _altCode.text.trim().isNotEmpty ? _altCode.text : _altName.text,
      );
      if (!mounted) return;
      if (alternative == null) {
        setState(
          () => _error =
              'Select a valid alternative item, or leave both alternative fields empty.',
        );
        return;
      }
    }
    final existing = await widget.remote.findExisting(
      product.itemCode,
      itemName: product.itemName,
    );
    if (!mounted) return;
    if (existing != null && existing.id != _editingId) {
      await _selectProduct(product);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.remote.save(
        id: _editingId,
        product: product,
        statusId: _statusId!,
        statusDate: _date,
        alternative: alternative,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 760),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(26, 22, 18, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xff102d42), Color(0xff174d68)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      color: Color(0xff77d4ff),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.initialRecord?.isPending == true
                            ? 'Review Pending Item'
                            : _editingId == null
                            ? 'Add Purchase Status'
                            : 'Edit Purchase Status',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Required fields are marked with *',
                        style: TextStyle(
                          color: Color(0xffbad0dc),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.initialRecord?.isPending == true) ...[
                      _PendingReviewBanner(record: widget.initialRecord!),
                      const SizedBox(height: 20),
                    ],
                    const _SectionTitle(
                      icon: Icons.inventory_2_outlined,
                      title: 'Main item',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _ProductLookupField(
                            remote: widget.remote,
                            controller: _itemCode,
                            label: 'Item code',
                            searchByCode: true,
                            onInputChanged: () =>
                                setState(() => _product = null),
                            onSelected: _selectProduct,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: _ProductLookupField(
                            remote: widget.remote,
                            controller: _itemName,
                            label: 'Item name *',
                            searchByCode: false,
                            onInputChanged: () =>
                                setState(() => _product = null),
                            onSelected: _selectProduct,
                          ),
                        ),
                      ],
                    ),
                    if (_product != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xfff4f9fd),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xffd8eaf4)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _AutoInfo(
                                label: 'Purchase status',
                                value: _product!.purchaseStatus,
                              ),
                            ),
                            Expanded(
                              child: _AutoInfo(
                                label: 'Category',
                                value: _product!.category,
                              ),
                            ),
                            Expanded(
                              child: _AutoInfo(
                                label: 'Supplier',
                                value: _product!.supplier,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      icon: Icons.flag_outlined,
                      title: 'Status information',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(
                              'status-$_statusId-$_addingCustomStatus',
                            ),
                            initialValue: _statusId,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              'Status *',
                              Icons.sell_outlined,
                            ),
                            items: [
                              ..._statuses.map(
                                (status) => DropdownMenuItem(
                                  value: status.id,
                                  child: Text(
                                    status.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const DropdownMenuItem(
                                value: -1,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.add_circle_outline_rounded,
                                      size: 19,
                                      color: AppColors.primaryColor,
                                    ),
                                    SizedBox(width: 9),
                                    Text(
                                      'Other — add new status',
                                      style: TextStyle(
                                        color: AppColors.primaryColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == -1) {
                                setState(() {
                                  _addingCustomStatus = true;
                                  _error = null;
                                });
                              } else {
                                setState(() {
                                  _statusId = value;
                                  _addingCustomStatus = false;
                                  if (value != _initialStatusId) {
                                    _date = DateTime.now();
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(13),
                            child: InputDecorator(
                              decoration: _inputDecoration(
                                'Date of last status *',
                                Icons.calendar_month_outlined,
                              ),
                              child: Text(
                                DateFormat('dd MMMM yyyy').format(_date),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: !_addingCustomStatus
                          ? const SizedBox.shrink()
                          : Container(
                              key: const ValueKey('custom-status-field'),
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xfff3f8fc),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xffd6e9f5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _customStatus,
                                      autofocus: true,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      onSubmitted: (_) => _addStatus(),
                                      decoration: _inputDecoration(
                                        'New status name',
                                        Icons.edit_outlined,
                                      ).copyWith(fillColor: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton.icon(
                                    onPressed: _savingCustomStatus
                                        ? null
                                        : _addStatus,
                                    icon: _savingCustomStatus
                                        ? const SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.check_rounded),
                                    label: const Text('Add'),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 18,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: 'Cancel',
                                    onPressed: _savingCustomStatus
                                        ? null
                                        : () => setState(() {
                                            _addingCustomStatus = false;
                                            _customStatus.clear();
                                          }),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      icon: Icons.swap_horiz_rounded,
                      title: 'Alternative item (optional)',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _ProductLookupField(
                            remote: widget.remote,
                            controller: _altCode,
                            label: 'Alternative item code',
                            searchByCode: true,
                            onInputChanged: () =>
                                setState(() => _alternative = null),
                            onSelected: (product) => setState(() {
                              _alternative = product;
                              _altCode.text = product.itemCode;
                              _altName.text = product.itemName;
                            }),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: _ProductLookupField(
                            remote: widget.remote,
                            controller: _altName,
                            label: 'Alternative item name',
                            searchByCode: false,
                            onInputChanged: () =>
                                setState(() => _alternative = null),
                            onSelected: (product) => setState(() {
                              _alternative = product;
                              _altCode.text = product.itemCode;
                              _altName.text = product.itemName;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _note,
                      maxLines: 3,
                      decoration: _inputDecoration(
                        'Note (optional)',
                        Icons.notes_rounded,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade800),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              decoration: const BoxDecoration(
                color: Color(0xfff8fafc),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
                border: Border(top: BorderSide(color: Color(0xffe8edf2))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      widget.initialRecord?.isPending == true
                          ? 'Complete review'
                          : _editingId == null
                          ? 'Add item'
                          : 'Save changes',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 17,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
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

class _PendingReviewBanner extends StatelessWidget {
  final PurchaseStatusRecord record;

  const _PendingReviewBanner({required this.record});

  @override
  Widget build(BuildContext context) {
    final hasPreviousStatus = record.statusId != null;
    final alreadyExists = record.wasAlreadyExisting;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xfffff8e8), Color(0xfffffcf4)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffffd78a)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xffffe7b5),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.pending_actions_rounded,
              color: Color(0xffb66d00),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alreadyExists
                      ? 'Already exists in Purchase Status'
                      : 'New item awaiting its first purchase status',
                  style: const TextStyle(
                    color: Color(0xff5c3a00),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alreadyExists && hasPreviousStatus
                      ? 'Previous status: ${record.statusName}. Keep it or choose a new status, then complete the review.'
                      : alreadyExists
                      ? 'This item was received before and is still awaiting a status. Complete its review now.'
                      : 'Select a status and complete the review. Catalog details were filled automatically when available.',
                  style: const TextStyle(
                    color: Color(0xff87601c),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: alreadyExists
                  ? const Color(0xffffe7e7)
                  : const Color(0xffe5f7ef),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              alreadyExists ? 'ALREADY EXISTS' : 'NEW ITEM',
              style: TextStyle(
                color: alreadyExists
                    ? const Color(0xffb42318)
                    : const Color(0xff087a5b),
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductLookupField extends StatefulWidget {
  final PurchaseStatusRemoteDs remote;
  final TextEditingController controller;
  final String label;
  final bool searchByCode;
  final VoidCallback onInputChanged;
  final ValueChanged<PurchaseProductSuggestion> onSelected;

  const _ProductLookupField({
    required this.remote,
    required this.controller,
    required this.label,
    required this.searchByCode,
    required this.onInputChanged,
    required this.onSelected,
  });

  @override
  State<_ProductLookupField> createState() => _ProductLookupFieldState();
}

class _ProductLookupFieldState extends State<_ProductLookupField> {
  Timer? _debounce;
  Timer? _focusDismissTimer;
  List<PurchaseProductSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _focused = false;
  late final FocusNode _focusNode;
  final LayerLink _suggestionsLink = LayerLink();
  OverlayEntry? _suggestionsOverlay;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusDismissTimer?.cancel();
    _hideSuggestionsOverlay();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      _focusDismissTimer?.cancel();
      _showSuggestionsOverlay();
    } else {
      // On web the field can lose focus on pointer-down before ListTile.onTap
      // fires. Keep the overlay alive briefly so the click reaches the item.
      _focusDismissTimer?.cancel();
      _focusDismissTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted && !_focusNode.hasFocus) _hideSuggestionsOverlay();
      });
    }
  }

  void _showSuggestionsOverlay() {
    if (!mounted || !_focused || _suggestions.isEmpty) {
      _hideSuggestionsOverlay();
      return;
    }
    if (_suggestionsOverlay == null) {
      _suggestionsOverlay = OverlayEntry(
        builder: (_) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return const SizedBox.shrink();
          final desiredWidth =
              box.size.width * (widget.searchByCode ? 1.55 : 1.15);
          final maxWidth = box.size.width > 760 ? box.size.width : 760.0;
          final expandedWidth = desiredWidth
              .clamp(box.size.width, maxWidth)
              .toDouble();
          return Positioned(
            width: expandedWidth,
            child: CompositedTransformFollower(
              link: _suggestionsLink,
              showWhenUnlinked: false,
              offset: Offset(0, box.size.height + 6),
              child: _suggestionsCard(),
            ),
          );
        },
      );
      Overlay.of(context).insert(_suggestionsOverlay!);
    } else {
      _suggestionsOverlay!.markNeedsBuild();
    }
  }

  void _hideSuggestionsOverlay() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
  }

  void _search(String value) {
    widget.onInputChanged();
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _suggestions = const []);
      _hideSuggestionsOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      setState(() => _searching = true);
      try {
        final results = await widget.remote.searchProducts(value);
        if (mounted && widget.controller.text == value) {
          setState(() => _suggestions = results);
          _showSuggestionsOverlay();
        }
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Widget _suggestionsCard() {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xffdce3eb)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30172b3d),
              blurRadius: 22,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 5),
            itemCount: _suggestions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _suggestions[index];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xffedf6fc),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.medication_outlined,
                      size: 18,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  title: Text(
                    item.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${item.itemCode}  •  ${item.category}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    _hideSuggestionsOverlay();
                    setState(() => _suggestions = const []);
                    _focusNode.unfocus();
                    widget.onSelected(item);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _suggestionsLink,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            onChanged: _search,
            decoration:
                _inputDecoration(
                  widget.label,
                  widget.searchByCode
                      ? Icons.qr_code_2_rounded
                      : Icons.search_rounded,
                ).copyWith(
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
          ),
          if (_focused &&
              _suggestions.isNotEmpty &&
              _suggestionsOverlay == null)
            Positioned(
              top: 64,
              left: 0,
              right: 0,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xffdce3eb)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1a172b3d),
                      blurRadius: 16,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _suggestions[index];
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xffedf6fc),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.medication_outlined,
                            size: 18,
                            color: AppColors.primaryColor,
                          ),
                        ),
                        title: Text(
                          item.itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${item.itemCode}  •  ${item.category}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          setState(() => _suggestions = const []);
                          _focusNode.unfocus();
                          widget.onSelected(item);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryDialog extends StatelessWidget {
  final PurchaseStatusRemoteDs remote;
  final PurchaseStatusRecord record;

  const _HistoryDialog({required this.remote, required this.record});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('History — ${record.itemCode}'),
      content: SizedBox(
        width: 760,
        height: 430,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: remote.fetchHistory(record.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text(_friendlyError(snapshot.error!)));
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return const _EmptyState(
                icon: Icons.history_toggle_off_rounded,
                title: 'No previous versions',
                message: 'Changes and deletion snapshots will appear here.',
              );
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final row = rows[index];
                final operation = (row['operation'] ?? 'UPDATE').toString();
                final changed = DateTime.tryParse(
                  (row['changed_at'] ?? '').toString(),
                )?.toLocal();
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xfff8fafc),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xffe4e9ef)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusChip(operation),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['status_name'] ?? ''} • ${row['status_date'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Alternative: ${row['alternative_item_code'] ?? '—'}  |  Note: ${row['note'] ?? '—'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.subText),
                            ),
                          ],
                        ),
                      ),
                      if (changed != null)
                        Text(
                          DateFormat('dd MMM yyyy, HH:mm').format(changed),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.subText,
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19, color: AppColors.primaryColor),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppColors.text,
        ),
      ),
    ],
  );
}

class _AutoInfo extends StatelessWidget {
  final String label;
  final String value;
  const _AutoInfo({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: AppColors.subText, fontSize: 11),
      ),
      const SizedBox(height: 4),
      Text(
        value.isEmpty ? '—' : value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
    ],
  );
}

class _StatusChip extends StatelessWidget {
  final String value;
  const _StatusChip(this.value);
  @override
  Widget build(BuildContext context) {
    final upper = value.toUpperCase();
    final color = upper.contains('AVAILABLE') && !upper.contains('NOT')
        ? const Color(0xff0f9f7f)
        : upper.contains('OUT OF STOCK') || upper.contains('DELETE')
        ? const Color(0xffd95050)
        : upper.contains('PENDING')
        ? const Color(0xffd58a12)
        : AppColors.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xffedf6fc),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 34, color: AppColors.primaryColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.subText),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

InputDecoration _inputDecoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: const Color(0xfffafbfd),
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xffdfe5ec)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xffdfe5ec)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xff4eb0de), width: 1.5),
    ),
  );
}

String _friendlyError(Object error) {
  if (error is TimeoutException) {
    return 'Loading took longer than 25 seconds. Check the Supabase connection and try again.';
  }
  if (error is FormatException) return error.message;
  final text = error.toString();
  if (text.contains('purchase_status_items') ||
      text.contains('purchase_status_options')) {
    return 'Purchase tables are not ready. Run supabase/sql/purchase_status_module.sql in Supabase first.';
  }
  if (text.contains('duplicate key')) return 'This value already exists.';
  return text.replaceFirst('Exception: ', '');
}

ThemeData _purchaseThemeData(ThemeData baseTheme) {
  return baseTheme.copyWith(
    colorScheme: baseTheme.colorScheme.copyWith(
      primary: AppColors.primaryColor,
      onPrimary: Colors.white,
      secondary: AppColors.primaryColor,
      onSecondary: Colors.white,
      surface: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        iconColor: Colors.white,
      ),
    ),
    dialogTheme: baseTheme.dialogTheme.copyWith(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    datePickerTheme: baseTheme.datePickerTheme.copyWith(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: AppColors.primaryColor,
      headerForegroundColor: Colors.white,
    ),
  );
}
