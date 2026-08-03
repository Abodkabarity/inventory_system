import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:daily_order/core/theme/app_colors.dart';
import 'package:daily_order/core/utils/stock_check_excel_exporter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import '../../../domain/entities/stock_check_task.dart';

class BranchStockCheckPage extends StatefulWidget {
  final String branchName;
  final VoidCallback? onBack;
  final bool embedded;

  const BranchStockCheckPage({
    super.key,
    required this.branchName,
    this.onBack,
    this.embedded = false,
  });

  @override
  State<BranchStockCheckPage> createState() => _BranchStockCheckPageState();
}

class _BranchStockCheckPageState extends State<BranchStockCheckPage> {
  final _client = Supabase.instance.client;
  final _systemControllers = <String, TextEditingController>{};
  final _actualControllers = <String, TextEditingController>{};
  final _barcodeStickerValues = <String, bool?>{};
  final _itemStatusValues = <String, String?>{};
  final _autosaveTimers = <String, Timer>{};
  final _autosavingIds = <String>{};
  final _dirtyDraftIds = <String>{};
  final _lastSavedDraftSignatures = <String, String>{};
  Timer? _deadlineTicker;
  Timer? _draftSyncTimer;
  List<StockCheckTask> _rows = [];
  Map<String, _StockCheckItemMeta> _itemMetaByCode = {};
  String? _selectedBatchId;
  bool _loading = true;
  bool _saving = false;
  bool _importing = false;
  bool _exporting = false;
  double _importProgress = 0;
  String _importStage = '';
  String _error = '';
  String _message = '';

  @override
  void initState() {
    super.initState();
    _deadlineTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _draftSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _syncCompletedDrafts();
    });
    _load();
  }

  @override
  void dispose() {
    for (final timer in _autosaveTimers.values) {
      timer.cancel();
    }
    _deadlineTicker?.cancel();
    _draftSyncTimer?.cancel();
    for (final controller in _systemControllers.values) {
      controller.dispose();
    }
    for (final controller in _actualControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
      _itemMetaByCode = {};
    });
    try {
      final res = await _client
          .from('stock_check_tasks')
          .select()
          .eq('branch_name', widget.branchName)
          .order('sent_at', ascending: false);
      final rows = List<Map<String, dynamic>>.from(
        res,
      ).map(StockCheckTask.fromMap).toList();
      for (final row in rows) {
        _systemControllers.putIfAbsent(
          row.id,
          () => TextEditingController(text: row.systemQty?.toString() ?? ''),
        );
        _actualControllers.putIfAbsent(
          row.id,
          () => TextEditingController(text: row.actualQty?.toString() ?? ''),
        );
        if (row.includeBarcodeStickerCheck) {
          _barcodeStickerValues.putIfAbsent(
            row.id,
            () => row.barcodeStickerIsCorrect,
          );
        }
        if (row.requiresItemStatus) {
          _itemStatusValues.putIfAbsent(
            row.id,
            () => row.itemStatusValue.isEmpty ? null : row.itemStatusValue,
          );
        }
        if (_parseQty(_systemControllers[row.id]?.text ?? '') != null &&
            _parseQty(_actualControllers[row.id]?.text ?? '') != null) {
          _lastSavedDraftSignatures[row.id] ??= _draftSignature(row);
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
      unawaited(_refreshItemMeta(rows));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshItemMeta(List<StockCheckTask> rows) async {
    final itemMetaByCode = await _loadItemMeta(rows);
    if (!mounted) return;
    setState(() => _itemMetaByCode = itemMetaByCode);
  }

  Future<Map<String, _StockCheckItemMeta>> _loadItemMeta(
    List<StockCheckTask> rows,
  ) async {
    final codes = rows
        .map((row) => _normalizeItemCode(row.itemCode))
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList();
    if (codes.isEmpty) return {};

    final result = <String, _StockCheckItemMeta>{};
    try {
      for (var i = 0; i < codes.length; i += 800) {
        final end = (i + 800).clamp(0, codes.length);
        final chunk = codes.sublist(i, end);
        final res = await _client
            .from('item_report')
            .select('item_code,category,sub_category,company')
            .inFilter('item_code', chunk);
        for (final raw in List<Map<String, dynamic>>.from(res)) {
          final code = _normalizeItemCode((raw['item_code'] ?? '').toString());
          if (code.isEmpty) continue;
          result[code] = _StockCheckItemMeta(
            category: (raw['category'] ?? '').toString().trim(),
            subCategory: (raw['sub_category'] ?? '').toString().trim(),
            company: (raw['company'] ?? '').toString().trim(),
          );
        }
      }
    } catch (_) {
      return result;
    }
    return result;
  }

  Future<void> _submitBatch(List<StockCheckTask> rows) async {
    if (_batchExpired(rows)) {
      setState(() {
        _error = 'This stock check has expired. Editing and submit are closed.';
        _message = '';
      });
      return;
    }

    final missingItemStatuses = rows.where((row) {
      if (!row.requiresItemStatus) return false;
      final system = _parseQty(_systemControllers[row.id]?.text ?? '');
      final actual = _parseQty(_actualControllers[row.id]?.text ?? '');
      if (system == null || actual == null) return false;
      return (_itemStatusValues[row.id] ?? '').trim().isEmpty;
    }).length;
    if (missingItemStatuses > 0) {
      setState(() {
        _error =
            'Select Item Status for $missingItemStatuses completed item(s) before submitting.';
        _message = '';
      });
      return;
    }

    final submitter = await showDialog<_SubmitterInfo>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black38,
      builder: (_) => const _StockCheckSubmitterDialog(),
    );
    if (submitter == null || !mounted) return;

    setState(() {
      _saving = true;
      _error = '';
      _message = '';
    });
    try {
      final now = DateTime.now().toIso8601String();
      final completedRows = <StockCheckTask>[];
      final submittedByThisUserIds = <String>{};
      final payload = <Map<String, dynamic>>[];
      for (final row in rows) {
        final systemText = _systemControllers[row.id]?.text.trim() ?? '';
        final actualText = _actualControllers[row.id]?.text.trim() ?? '';
        final system = _parseQty(systemText);
        final actual = _parseQty(actualText);
        if (system == null || actual == null) continue;
        final itemStatus = (_itemStatusValues[row.id] ?? '').trim();
        if (row.requiresItemStatus && itemStatus.isEmpty) continue;
        final currentSignature = _draftSignature(row);
        final alreadySubmitted = row.isSubmitted;
        final submittedRowChanged =
            alreadySubmitted &&
            _lastSavedDraftSignatures[row.id] != currentSignature;
        final shouldClaimSubmitter = !alreadySubmitted || submittedRowChanged;
        if (alreadySubmitted && !submittedRowChanged) {
          continue;
        }
        completedRows.add(row);
        if (shouldClaimSubmitter) {
          submittedByThisUserIds.add(row.id);
        }
        payload.add({
          'id': row.id,
          'batch_id': row.batchId,
          'title': row.title,
          'source': row.source,
          'branch_name': row.branchName,
          'item_code': row.itemCode,
          'item_name': row.itemName,
          'system_qty': system,
          'actual_qty': actual,
          'include_barcode_sticker_check': row.includeBarcodeStickerCheck,
          if (row.includeBarcodeStickerCheck)
            'barcode_sticker_is_correct': _barcodeStickerValues[row.id],
          'include_item_status': row.includeItemStatus,
          'item_status_options': row.itemStatusOptions,
          'item_status_value': row.requiresItemStatus ? itemStatus : null,
          'status': 'submitted',
          'note': row.note,
          'sent_at': row.sentAt?.toIso8601String(),
          'expires_at': row.expiresAt?.toIso8601String(),
          'submitted_at': now,
          if (shouldClaimSubmitter) 'submitted_by_name': submitter.name,
          if (shouldClaimSubmitter)
            'submitted_by_employee_id': submitter.employeeId,
          'updated_at': now,
        });
      }

      for (var i = 0; i < payload.length; i += 500) {
        final end = (i + 500).clamp(0, payload.length);
        await _client
            .from('stock_check_tasks')
            .upsert(payload.sublist(i, end), onConflict: 'id');
      }

      if (!mounted) return;
      setState(() {
        final submittedIds = completedRows.map((row) => row.id).toSet();
        _rows = _rows.map((row) {
          if (!submittedIds.contains(row.id)) return row;
          return row.copyWith(
            systemQty: _parseQty(_systemControllers[row.id]?.text ?? ''),
            actualQty: _parseQty(_actualControllers[row.id]?.text ?? ''),
            barcodeStickerIsCorrect: row.includeBarcodeStickerCheck
                ? _barcodeStickerValues[row.id]
                : row.barcodeStickerIsCorrect,
            itemStatusValue: row.requiresItemStatus
                ? (_itemStatusValues[row.id] ?? '')
                : row.itemStatusValue,
            status: 'submitted',
            submittedAt: DateTime.tryParse(now),
            submittedByName: submittedByThisUserIds.contains(row.id)
                ? submitter.name
                : row.submittedByName,
            submittedByEmployeeId: submittedByThisUserIds.contains(row.id)
                ? submitter.employeeId
                : row.submittedByEmployeeId,
          );
        }).toList();
        for (final row in completedRows) {
          _dirtyDraftIds.remove(row.id);
          _lastSavedDraftSignatures[row.id] = _draftSignature(row);
        }
        _message = completedRows.isEmpty
            ? 'No new or edited completed items were submitted. Existing submitted items kept their original checker names.'
            : 'Saved ${completedRows.length} item(s). Existing submitted items kept their original checker names unless their quantities were edited.';
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  num? _parseQty(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return num.tryParse(text.replaceAll(',', ''));
  }

  bool _batchExpired(List<StockCheckTask> rows) {
    final expiresAt = _batchExpiresAt(rows);
    return expiresAt != null && DateTime.now().isAfter(expiresAt);
  }

  DateTime? _batchExpiresAt(List<StockCheckTask> rows) {
    final dates = rows
        .map((row) => row.expiresAt?.toLocal())
        .whereType<DateTime>()
        .toList();
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.first;
  }

  void _scheduleAutosave(StockCheckTask row, {bool force = false}) {
    if ((!force && row.isSubmitted) || row.isExpired || _importing) return;
    _dirtyDraftIds.add(row.id);
    _autosaveTimers[row.id]?.cancel();
    _autosaveTimers[row.id] = Timer(const Duration(milliseconds: 900), () {
      _saveRowDraft(row, requireCompleteDraft: true);
    });
  }

  Future<bool> _saveRowDraft(
    StockCheckTask row, {
    bool markSubmitted = false,
    String? submittedAtIso,
    bool requireCompleteDraft = false,
  }) async {
    if (row.isExpired) return false;
    final systemText = _systemControllers[row.id]?.text.trim() ?? '';
    final actualText = _actualControllers[row.id]?.text.trim() ?? '';
    final system = _parseQty(systemText);
    final actual = _parseQty(actualText);
    final itemStatus = (_itemStatusValues[row.id] ?? '').trim();
    if ((systemText.isNotEmpty && system == null) ||
        (actualText.isNotEmpty && actual == null)) {
      return false;
    }
    if (requireCompleteDraft &&
        (system == null ||
            actual == null ||
            (row.requiresItemStatus && itemStatus.isEmpty))) {
      return false;
    }
    final signature = _draftSignature(row);
    if (!markSubmitted && _lastSavedDraftSignatures[row.id] == signature) {
      _dirtyDraftIds.remove(row.id);
      return false;
    }
    if (mounted) setState(() => _autosavingIds.add(row.id));
    try {
      final now = DateTime.now().toIso8601String();
      await _client
          .from('stock_check_tasks')
          .update({
            'system_qty': system,
            'actual_qty': actual,
            if (row.includeBarcodeStickerCheck)
              'barcode_sticker_is_correct': _barcodeStickerValues[row.id],
            if (row.requiresItemStatus) 'item_status_value': itemStatus,
            if (markSubmitted) 'status': 'submitted',
            if (markSubmitted) 'submitted_at': submittedAtIso ?? now,
            'updated_at': now,
          })
          .eq('id', row.id);
      _lastSavedDraftSignatures[row.id] = signature;
      _dirtyDraftIds.remove(row.id);
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Autosave failed for ${row.itemCode}: $e';
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _autosavingIds.remove(row.id));
    }
  }

  String _draftSignature(StockCheckTask row) {
    final systemText = _systemControllers[row.id]?.text.trim() ?? '';
    final actualText = _actualControllers[row.id]?.text.trim() ?? '';
    final barcode = row.includeBarcodeStickerCheck
        ? (_barcodeStickerValues[row.id]?.toString() ?? '')
        : '';
    final itemStatus = row.requiresItemStatus
        ? (_itemStatusValues[row.id] ?? '').trim()
        : '';
    return '$systemText|$actualText|$barcode|$itemStatus';
  }

  bool _hasCompleteDraft(StockCheckTask row) {
    if (row.isExpired) return false;
    final systemText = _systemControllers[row.id]?.text.trim() ?? '';
    final actualText = _actualControllers[row.id]?.text.trim() ?? '';
    final itemStatusComplete =
        !row.requiresItemStatus ||
        (_itemStatusValues[row.id] ?? '').trim().isNotEmpty;
    return _parseQty(systemText) != null &&
        _parseQty(actualText) != null &&
        itemStatusComplete;
  }

  bool _hasAnyDraftValue(StockCheckTask row) {
    final systemText = _systemControllers[row.id]?.text.trim() ?? '';
    final actualText = _actualControllers[row.id]?.text.trim() ?? '';
    return systemText.isNotEmpty ||
        actualText.isNotEmpty ||
        (_itemStatusValues[row.id] ?? '').trim().isNotEmpty ||
        row.systemQty != null ||
        row.actualQty != null;
  }

  Future<void> _syncCompletedDrafts() async {
    if (_loading || _saving || _importing || _rows.isEmpty) return;
    final rowsToSync = _rows.where((row) {
      if (row.isSubmitted || !_hasCompleteDraft(row)) return false;
      final signature = _draftSignature(row);
      return _dirtyDraftIds.contains(row.id) ||
          _lastSavedDraftSignatures[row.id] != signature;
    }).toList();
    for (var i = 0; i < rowsToSync.length; i++) {
      await _saveRowDraft(rowsToSync[i], requireCompleteDraft: true);
      if (i % 25 == 24) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
  }

  Future<Set<String>> _importSystemQty(
    List<StockCheckTask> rows, {
    Set<String> editableSubmittedIds = const {},
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null) return const {};
    if (bytes == null) {
      setState(() {
        _error = 'Could not read the selected STK Ledger file.';
        _message = '';
      });
      return const {};
    }

    setState(() {
      _importing = true;
      _importProgress = .06;
      _importStage = 'Preparing import';
      _error = '';
      _message = 'Importing STK Ledger...';
    });

    try {
      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return const {};
      setState(() {
        _importProgress = .18;
        _importStage = 'Reading STK Ledger file';
      });
      await SchedulerBinding.instance.endOfFrame;
      final importedRows = (await compute(_parseStockCheckImportRows, {
        'bytes': bytes,
        'extension': file.extension?.toLowerCase() ?? '',
      })).map(_ImportedStockQtyRow.fromMap).toList();
      if (!mounted) return const {};
      setState(() {
        _importProgress = .46;
        _importStage = 'Matching branch items';
      });
      await SchedulerBinding.instance.endOfFrame;
      final byCode = {for (final row in rows) _norm(row.itemCode): row};
      final byName = {for (final row in rows) _norm(row.itemName): row};
      final protectedExistingRows = rows.where((row) {
        if (editableSubmittedIds.contains(row.id)) return false;
        return row.isSubmitted || _hasAnyDraftValue(row);
      }).toList();
      var overwriteExisting = false;
      if (protectedExistingRows.isNotEmpty) {
        final decision = await _askImportExistingValuesDecision(
          protectedExistingRows.length,
        );
        if (!mounted) return const {};
        if (decision == null) {
          setState(() {
            _message = 'STK Ledger import cancelled. No values were changed.';
            _error = '';
            _importing = false;
            _importProgress = 0;
            _importStage = '';
          });
          return const {};
        }
        if (decision) {
          final confirmed = await _confirmOverwriteSubmittedImport(
            protectedExistingRows.length,
          );
          if (!mounted) return const {};
          if (confirmed != true) {
            setState(() {
              _message =
                  'STK Ledger import cancelled. Existing values were not changed.';
              _error = '';
              _importing = false;
              _importProgress = 0;
              _importStage = '';
            });
            return const {};
          }
          overwriteExisting = true;
        }
      }
      final matchedIds = <String>{};
      final overwrittenIds = <String>{};
      var applied = 0;
      var protectedSkipped = 0;
      var skippedBranch = 0;
      var notFound = 0;

      for (var i = 0; i < importedRows.length; i++) {
        final imported = importedRows[i];
        if (_norm(imported.branchName) != _norm(widget.branchName)) {
          skippedBranch++;
        } else {
          final match =
              byCode[_norm(imported.itemCode)] ??
              byName[_norm(imported.itemName)];
          if (match == null) {
            notFound++;
          } else {
            final protectedExisting =
                (match.isSubmitted || _hasAnyDraftValue(match)) &&
                !editableSubmittedIds.contains(match.id) &&
                !overwriteExisting;
            if (protectedExisting) {
              protectedSkipped++;
              continue;
            }
            if (overwriteExisting &&
                match.isSubmitted &&
                !editableSubmittedIds.contains(match.id)) {
              overwrittenIds.add(match.id);
            }
            _systemControllers[match.id]?.text = imported.actualQtyText;
            matchedIds.add(match.id);
            applied++;
          }
        }

        if (i % 300 == 0) {
          if (!mounted) return const {};
          final progress = importedRows.isEmpty ? 1.0 : i / importedRows.length;
          setState(() {
            _importProgress = .46 + (.34 * progress);
            _importStage = 'Matching ${i + 1} of ${importedRows.length} items';
          });
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }

      if (!mounted) return const {};
      setState(() {
        _importProgress = .82;
        _importStage = 'Applying missing items as 0';
      });
      await SchedulerBinding.instance.endOfFrame;
      var setToZero = 0;
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (matchedIds.contains(row.id)) continue;
        final protectedExisting =
            (row.isSubmitted || _hasAnyDraftValue(row)) &&
            !editableSubmittedIds.contains(row.id) &&
            !overwriteExisting;
        if (protectedExisting) continue;
        if (overwriteExisting &&
            row.isSubmitted &&
            !editableSubmittedIds.contains(row.id)) {
          overwrittenIds.add(row.id);
        }
        _systemControllers[row.id]?.text = '0';
        setToZero++;
        if (i % 150 == 0) {
          if (!mounted) return const {};
          final progress = rows.isEmpty ? 1.0 : i / rows.length;
          setState(() {
            _importProgress = .82 + (.14 * progress);
            _importStage = 'Applying quantities';
          });
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }

      if (!mounted) return const {};
      setState(() {
        _message =
            'Imported STK Ledger for $applied item(s). $setToZero item(s) not found were set to 0. Protected $protectedSkipped existing item(s). Skipped $skippedBranch other branch item(s), $notFound unmatched item(s).';
        _error = '';
        _importing = false;
        _importProgress = 1;
        _importStage = '';
      });
      await _syncCompletedDrafts();
      return overwrittenIds;
    } catch (e) {
      if (!mounted) return const {};
      setState(() {
        _error = e.toString();
        _message = '';
        _importing = false;
        _importProgress = 0;
        _importStage = '';
      });
      return const {};
    }
  }

  Future<void> _exportBatch(List<StockCheckTask> rows) async {
    if (rows.isEmpty || _exporting) return;
    setState(() {
      _exporting = true;
      _error = '';
      _message = '';
    });
    try {
      await SchedulerBinding.instance.endOfFrame;
      await StockCheckExcelExporter.exportBranchResult(
        rows: rows,
        title: rows.first.title,
      );
      if (!mounted) return;
      setState(() {
        _message = 'Stock check export is ready.';
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Export failed: $e';
        _message = '';
      });
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<bool?> _askImportExistingValuesDecision(int existingCount) {
    return showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
        contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
        actionsPadding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFD97706),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Existing values already found',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Text(
            'This stock check has $existingCount item(s) with saved or submitted quantities. These may include values entered by the branch earlier, even if Submit was not pressed yet.\n\n'
            'Choose what the import should do:\n\n'
            '- Pending only: update only empty items. Items that already have values will stay exactly as they are.\n'
            '- Overwrite existing: allow the new STK Ledger import to replace old System Qty values for items that already have values.\n\n'
            'Items currently opened with the blue Edit button are allowed to update normally.',
            style: const TextStyle(
              color: Color(0xFF334155),
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text(
              'Cancel import',
              style: TextStyle(color: AppColors.secondaryColor),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
            ),
            child: const Text(
              'Pending only',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Overwrite existing'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmOverwriteSubmittedImport(int existingCount) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
        contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
        actionsPadding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        title: const Text(
          'Final confirmation',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: SizedBox(
          width: 500,
          child: Text(
            'Are you completely sure?\n\n'
            'If you continue, the import can change System Qty for $existingCount item(s) that already have saved or submitted values. This means values entered before may be replaced by the new STK Ledger values. Items missing from the file may become 0.\n\n'
            'Press Confirm only if this is intentional.',
            style: const TextStyle(
              color: Color(0xFF334155),
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, keep old values'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm overwrite'),
          ),
        ],
      ),
    );
  }

  Map<String, List<StockCheckTask>> _batches() {
    final map = <String, List<StockCheckTask>>{};
    for (final row in _rows) {
      map.putIfAbsent(row.batchId, () => []).add(row);
    }
    return map;
  }

  List<List<StockCheckTask>> _sortedBatchLists(
    Iterable<List<StockCheckTask>> batches,
  ) {
    final sorted = batches.map((rows) => [...rows]).toList();
    sorted.sort((a, b) {
      final aPending = a.where((row) => row.isPending).length;
      final bPending = b.where((row) => row.isPending).length;
      final aHasPending = aPending > 0;
      final bHasPending = bPending > 0;
      if (aHasPending != bHasPending) return aHasPending ? -1 : 1;
      if (aPending != bPending) return bPending.compareTo(aPending);
      return _latestSentAt(b).compareTo(_latestSentAt(a));
    });
    return sorted;
  }

  DateTime _latestSentAt(List<StockCheckTask> rows) {
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final row in rows) {
      final sentAt = row.sentAt;
      if (sentAt != null && sentAt.isAfter(latest)) latest = sentAt;
    }
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    final batches = _batches();
    final selectedRows = _selectedBatchId == null
        ? null
        : batches[_selectedBatchId!] ?? const <StockCheckTask>[];

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: widget.embedded
                ? EdgeInsets.zero
                : const EdgeInsets.all(18),
            child: Column(
              children: [
                _Header(
                  branchName: widget.branchName,
                  pending: _rows.where((e) => e.isPending).length,
                  submitted: _rows.where((e) => e.isSubmitted).length,
                  onBack: widget.onBack,
                  onRefresh: _load,
                  embedded: widget.embedded,
                ),
                if (_error.isNotEmpty) _Banner(message: _error, ok: false),
                if (_message.isNotEmpty) _Banner(message: _message, ok: true),
                const SizedBox(height: 14),
                Expanded(
                  child: selectedRows == null
                      ? _BatchGrid(
                          batches: _sortedBatchLists(batches.values),
                          onOpen: (batchId) {
                            setState(() => _selectedBatchId = batchId);
                          },
                        )
                      : _BatchEditor(
                          rows: selectedRows,
                          itemMetaByCode: _itemMetaByCode,
                          systemControllers: _systemControllers,
                          actualControllers: _actualControllers,
                          barcodeStickerValues: _barcodeStickerValues,
                          itemStatusValues: _itemStatusValues,
                          onBarcodeStickerChanged: (id, value) {
                            final row = selectedRows.firstWhere(
                              (item) => item.id == id,
                            );
                            setState(() => _barcodeStickerValues[id] = value);
                            _scheduleAutosave(row);
                          },
                          onItemStatusChanged: (id, value) {
                            final row = selectedRows.firstWhere(
                              (item) => item.id == id,
                            );
                            setState(() => _itemStatusValues[id] = value);
                            _scheduleAutosave(row, force: true);
                          },
                          saving: _saving,
                          importing: _importing,
                          exporting: _exporting,
                          expired: _batchExpired(selectedRows),
                          expiresAt: _batchExpiresAt(selectedRows),
                          autosavingIds: _autosavingIds,
                          importProgress: _importProgress,
                          importStage: _importStage,
                          onRowChanged: (row) =>
                              _scheduleAutosave(row, force: true),
                          onBack: () {
                            setState(() => _selectedBatchId = null);
                          },
                          onImport: (editableSubmittedIds) => _importSystemQty(
                            selectedRows,
                            editableSubmittedIds: editableSubmittedIds,
                          ),
                          onSubmit: () => _submitBatch(selectedRows),
                          onExport: () => _exportBatch(selectedRows),
                        ),
                ),
              ],
            ),
          );

    if (widget.embedded) {
      return ColoredBox(color: const Color(0xFFF4F7FB), child: content);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(child: content),
    );
  }
}

String _norm(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _headerKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

List<_ImportedStockQtyRow> _readStockCheckCsv(Uint8List bytes) {
  String text;
  try {
    text = utf8.decode(bytes);
  } catch (_) {
    text = latin1.decode(bytes);
  }
  final table = const CsvToListConverter().convert(text);
  return _rowsFromTable(table);
}

List<Map<String, String>> _parseStockCheckImportRows(
  Map<String, Object?> args,
) {
  final bytes = args['bytes']! as Uint8List;
  final extension = (args['extension'] ?? '').toString().toLowerCase();
  final rows = extension == 'csv'
      ? _readStockCheckCsv(bytes)
      : _readStockCheckXlsx(bytes);
  return rows.map((row) => row.toMap()).toList();
}

List<_ImportedStockQtyRow> _readStockCheckXlsx(Uint8List bytes) {
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
      final ref = cell.getAttribute('r') ?? '';
      final index = _columnIndex(ref);
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
  return _rowsFromTable(table);
}

int _columnIndex(String cellRef) {
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

List<_ImportedStockQtyRow> _rowsFromTable(List<List<dynamic>> table) {
  if (table.isEmpty) return const [];
  final headers = table.first.map((e) => _headerKey(e.toString())).toList();
  int findColumn(List<String> names) {
    for (final name in names.map(_headerKey)) {
      final index = headers.indexOf(name);
      if (index >= 0) return index;
    }
    return -1;
  }

  final branchIndex = findColumn(['Branch']);
  final itemCodeIndex = findColumn(['Item Code', 'ItemCode']);
  final itemNameIndex = findColumn(['Item Name', 'ItemName']);
  final actualQtyIndex = findColumn(['Actual Qty', 'ActualQty']);
  if ([
    branchIndex,
    itemCodeIndex,
    itemNameIndex,
    actualQtyIndex,
  ].any((e) => e < 0)) {
    throw Exception(
      'Import file must include Branch, Item Code, Item Name, and Actual Qty columns.',
    );
  }

  final rows = <_ImportedStockQtyRow>[];
  for (final raw in table.skip(1)) {
    String cell(int index) =>
        index < raw.length ? raw[index].toString().trim() : '';
    final branch = cell(branchIndex);
    final itemCode = cell(itemCodeIndex);
    final itemName = cell(itemNameIndex);
    final actualQty = cell(actualQtyIndex);
    if (branch.isEmpty || itemCode.isEmpty) continue;
    rows.add(
      _ImportedStockQtyRow(
        branchName: branch,
        itemCode: itemCode,
        itemName: itemName,
        actualQtyText: actualQty.isEmpty ? '0' : actualQty,
      ),
    );
  }
  return rows;
}

class _ImportedStockQtyRow {
  final String branchName;
  final String itemCode;
  final String itemName;
  final String actualQtyText;

  const _ImportedStockQtyRow({
    required this.branchName,
    required this.itemCode,
    required this.itemName,
    required this.actualQtyText,
  });

  factory _ImportedStockQtyRow.fromMap(Map<String, String> map) {
    return _ImportedStockQtyRow(
      branchName: map['branchName'] ?? '',
      itemCode: map['itemCode'] ?? '',
      itemName: map['itemName'] ?? '',
      actualQtyText: map['actualQtyText'] ?? '0',
    );
  }

  Map<String, String> toMap() {
    return {
      'branchName': branchName,
      'itemCode': itemCode,
      'itemName': itemName,
      'actualQtyText': actualQtyText,
    };
  }
}

class _SubmitterInfo {
  final String name;
  final String employeeId;

  const _SubmitterInfo({required this.name, required this.employeeId});
}

class _StockCheckSubmitterDialog extends StatefulWidget {
  const _StockCheckSubmitterDialog();

  @override
  State<_StockCheckSubmitterDialog> createState() =>
      _StockCheckSubmitterDialogState();
}

class _StockCheckSubmitterDialogState
    extends State<_StockCheckSubmitterDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _employeeIdController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _employeeIdController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _SubmitterInfo(
        name: _nameController.text.trim(),
        employeeId: _employeeIdController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 470,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondaryColor.withValues(alpha: .18),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundWidget,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primaryColor.withValues(alpha: .35),
                      ),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm stock check submit',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Enter your details before final submission.',
                          style: TextStyle(
                            color: AppColors.subText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SubmitterField(
                controller: _nameController,
                label: 'Your name',
                icon: Icons.person_rounded,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              _SubmitterField(
                controller: _employeeIdController,
                label: 'Employee ID',
                icon: Icons.badge_rounded,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.secondaryColor,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.secondaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Submit'),
                    ),
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

class _SubmitterField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _SubmitterField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: (value) {
        if ((value ?? '').trim().isEmpty) return '$label is required';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primaryColor),
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.primaryColor,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String branchName;
  final int pending;
  final int submitted;
  final VoidCallback? onBack;
  final VoidCallback onRefresh;
  final bool embedded;

  const _Header({
    required this.branchName,
    required this.pending,
    required this.submitted,
    required this.onBack,
    required this.onRefresh,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final headerCard = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD9E8F5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .055),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Back',
              onPressed: onBack ?? () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 10),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: Color(0xFF2563EB),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Stock Check',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    branchName,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            _Metric(
              label: 'Pending',
              value: pending,
              color: const Color(0xFFF97316),
            ),
            _Metric(
              label: 'Submitted',
              value: submitted,
              color: const Color(0xFF16A34A),
            ),
            IconButton.filledTonal(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );

    if (embedded) {
      return Align(alignment: Alignment.centerLeft, child: headerCard);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1320) {
          return Column(
            children: [
              Align(alignment: Alignment.center, child: headerCard),
              const SizedBox(height: 12),
              const _StockCheckHelpCard(compact: true),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            headerCard,
            const SizedBox(width: 18),
            const Expanded(child: _StockCheckHelpCard()),
          ],
        );
      },
    );
  }
}

class _StockCheckHelpCard extends StatelessWidget {
  final bool compact;

  const _StockCheckHelpCard({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('1', 'Import STK Ledger to fill System Qty from the ledger file.'),
      ('2', 'Count the physical stock and enter Actual Qty for each item.'),
      ('3', 'Press Submit Stock Check to save and confirm completed items.'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E8F5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Icon(
              Icons.tips_and_updates_rounded,
              color: Color(0xFF2563EB),
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How to complete this page',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                ...steps.map(
                  (step) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFFDBEAFE),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            step.$1,
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            step.$2,
                            maxLines: compact ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 12,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
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
        ],
      ),
    );
  }
}

class _BatchGrid extends StatelessWidget {
  final List<List<StockCheckTask>> batches;
  final ValueChanged<String> onOpen;

  const _BatchGrid({required this.batches, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (batches.isEmpty) {
      return const Center(
        child: Text(
          'No stock checks available.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(top: 4, right: 4, bottom: 18),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 520,
        mainAxisExtent: 320,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
      ),
      itemCount: batches.length,
      itemBuilder: (context, index) {
        final rows = batches[index];
        final first = rows.first;
        final pending = rows.where((e) => e.isPending).length;
        final submitted = rows.length - pending;
        final progress = rows.isEmpty ? 0.0 : submitted / rows.length;
        final sourceStyle = _StockCheckSourceStyle.fromSource(first.source);
        final expired = first.isExpired;
        final deadlineText = _batchDeadlineText(first.expiresAt);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onOpen(first.batchId),
            borderRadius: BorderRadius.circular(26),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: pending > 0
                      ? sourceStyle.border
                      : const Color(0xFFBBF7D0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: sourceStyle.color.withValues(alpha: .14),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 8, color: sourceStyle.color),
                    ),
                    Positioned(
                      right: -22,
                      top: -22,
                      child: Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          color: sourceStyle.background,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(26, 22, 22, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _SourceBadge(style: sourceStyle),
                              const Spacer(),
                              _SmallChip(
                                text: expired && pending > 0
                                    ? 'Expired'
                                    : pending > 0
                                    ? 'Pending'
                                    : 'Completed',
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: sourceStyle.background,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: sourceStyle.border),
                                ),
                                child: Icon(
                                  pending > 0
                                      ? Icons.assignment_late_rounded
                                      : Icons.verified_rounded,
                                  color: pending > 0
                                      ? sourceStyle.color
                                      : const Color(0xFF16A34A),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      first.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      _formatSentAt(first.sentAt),
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (deadlineText.isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
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
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 15),
                          Row(
                            children: [
                              _CardMetric(
                                label: 'Items',
                                value: rows.length.toString(),
                              ),
                              const SizedBox(width: 10),
                              _CardMetric(
                                label: 'Submitted',
                                value: submitted.toString(),
                              ),
                              const SizedBox(width: 10),
                              _CardMetric(
                                label: 'Pending',
                                value: pending.toString(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 9,
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    color: pending > 0
                                        ? sourceStyle.color
                                        : const Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${(progress * 100).round()}%',
                                style: TextStyle(
                                  color: pending > 0
                                      ? sourceStyle.color
                                      : const Color(0xFF16A34A),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: sourceStyle.color,
                                size: 22,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _formatSentAt(DateTime? sentAt) {
    if (sentAt == null) return 'Sent date not available';
    final local = sentAt.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'Sent $year-$month-$day at $hour:$minute';
  }

  static String _batchDeadlineText(DateTime? expiresAt) {
    if (expiresAt == null) return '';
    final local = expiresAt.toLocal();
    final remaining = local.difference(DateTime.now());
    if (remaining.isNegative) return 'Deadline expired';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    if (days > 0) return 'Time left $days d $hours h';
    if (hours > 0) return 'Time left $hours h $minutes m';
    return 'Time left $minutes m';
  }
}

class _CardMetric extends StatelessWidget {
  final String label;
  final String value;

  const _CardMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockCheckSourceStyle {
  final String label;
  final IconData icon;
  final Color color;
  final Color background;
  final Color border;

  const _StockCheckSourceStyle({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    required this.border,
  });

  factory _StockCheckSourceStyle.fromSource(String source) {
    final normalized = source.trim().toLowerCase();
    if (normalized == 'store') {
      return const _StockCheckSourceStyle(
        label: 'Store',
        icon: Icons.storefront_rounded,
        color: Color(0xFF059669),
        background: Color(0xFFECFDF5),
        border: Color(0xFFA7F3D0),
      );
    }
    return const _StockCheckSourceStyle(
      label: 'Inventory',
      icon: Icons.inventory_2_rounded,
      color: Color(0xFF2563EB),
      background: Color(0xFFEFF6FF),
      border: Color(0xFFBFDBFE),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final _StockCheckSourceStyle style;

  const _SourceBadge({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 16, color: style.color),
          const SizedBox(width: 6),
          Text(
            style.label,
            style: TextStyle(
              color: style.color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchEditor extends StatefulWidget {
  final List<StockCheckTask> rows;
  final Map<String, _StockCheckItemMeta> itemMetaByCode;
  final Map<String, TextEditingController> systemControllers;
  final Map<String, TextEditingController> actualControllers;
  final Map<String, bool?> barcodeStickerValues;
  final Map<String, String?> itemStatusValues;
  final void Function(String id, bool? value) onBarcodeStickerChanged;
  final void Function(String id, String? value) onItemStatusChanged;
  final bool saving;
  final bool importing;
  final bool exporting;
  final bool expired;
  final DateTime? expiresAt;
  final Set<String> autosavingIds;
  final double importProgress;
  final String importStage;
  final ValueChanged<StockCheckTask> onRowChanged;
  final VoidCallback onBack;
  final Future<Set<String>> Function(Set<String> editableSubmittedIds) onImport;
  final VoidCallback onSubmit;
  final VoidCallback onExport;

  const _BatchEditor({
    required this.rows,
    required this.itemMetaByCode,
    required this.systemControllers,
    required this.actualControllers,
    required this.barcodeStickerValues,
    required this.itemStatusValues,
    required this.onBarcodeStickerChanged,
    required this.onItemStatusChanged,
    required this.saving,
    required this.importing,
    required this.exporting,
    required this.expired,
    required this.expiresAt,
    required this.autosavingIds,
    required this.importProgress,
    required this.importStage,
    required this.onRowChanged,
    required this.onBack,
    required this.onImport,
    required this.onSubmit,
    required this.onExport,
  });

  @override
  State<_BatchEditor> createState() => _BatchEditorState();
}

class _BatchEditorState extends State<_BatchEditor> {
  final _searchController = TextEditingController();
  final _editingSubmittedIds = <String>{};
  String _search = '';
  String _statusFilter = 'all';
  final _categoryFilters = <String>{};
  final _subCategoryFilters = <String>{};
  final _companyFilters = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final showBarcodeSticker = rows.any(
      (row) => row.includeBarcodeStickerCheck,
    );
    final sourceStyle = _StockCheckSourceStyle.fromSource(rows.first.source);
    final categories = _optionsFromRows(rows, (meta) => meta.category);
    _categoryFilters.removeWhere((value) => !categories.contains(value));
    final categoryScopedRows = _categoryFilters.isEmpty
        ? rows
        : rows
              .where((row) => _categoryFilters.contains(_metaFor(row).category))
              .toList();
    final subCategories = _optionsFromRows(
      categoryScopedRows,
      (meta) => meta.subCategory,
    );
    _subCategoryFilters.removeWhere((value) => !subCategories.contains(value));
    final subCategoryScopedRows = _subCategoryFilters.isEmpty
        ? categoryScopedRows
        : categoryScopedRows
              .where(
                (row) =>
                    _subCategoryFilters.contains(_metaFor(row).subCategory),
              )
              .toList();
    final companies = _optionsFromRows(
      subCategoryScopedRows,
      (meta) => meta.company,
    );
    _companyFilters.removeWhere((value) => !companies.contains(value));
    final filteredRows = rows.where((row) {
      final needle = _search.trim().toLowerCase();
      final meta = _metaFor(row);
      final searchOk =
          needle.isEmpty ||
          row.itemName.toLowerCase().contains(needle) ||
          row.itemCode.toLowerCase().contains(needle) ||
          meta.category.toLowerCase().contains(needle) ||
          meta.subCategory.toLowerCase().contains(needle) ||
          meta.company.toLowerCase().contains(needle);
      final statusOk =
          _statusFilter == 'all' ||
          (_statusFilter == 'pending' && row.isPending) ||
          (_statusFilter == 'submitted' && row.isSubmitted);
      final categoryOk =
          _categoryFilters.isEmpty || _categoryFilters.contains(meta.category);
      final subCategoryOk =
          _subCategoryFilters.isEmpty ||
          _subCategoryFilters.contains(meta.subCategory);
      final companyOk =
          _companyFilters.isEmpty || _companyFilters.contains(meta.company);
      return searchOk && statusOk && categoryOk && subCategoryOk && companyOk;
    }).toList();
    filteredRows.sort(_compareRows);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD9E8F5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 10),
              _SourceBadge(style: sourceStyle),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  rows.first.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    widget.importing ||
                        widget.saving ||
                        widget.exporting ||
                        widget.expired
                    ? null
                    : () async {
                        final openedIds = await widget.onImport({
                          ..._editingSubmittedIds,
                        });
                        if (!mounted || openedIds.isEmpty) return;
                        setState(() {
                          _editingSubmittedIds.addAll(openedIds);
                        });
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.importing
                      ? const Color(0xFF0891B2)
                      : null,
                  backgroundColor: widget.importing
                      ? const Color(0xFFE0F7FE)
                      : null,
                  side: BorderSide(
                    color: widget.importing
                        ? const Color(0xFF06B6D4)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
                icon: widget.importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryColor,
                        ),
                      )
                    : const Icon(
                        Icons.upload_file_rounded,
                        size: 18,
                        color: AppColors.secondaryColor,
                      ),
                label: Text(
                  widget.importing
                      ? 'Importing STK Ledger...'
                      : 'Import STK Ledger',
                  style: TextStyle(
                    color: AppColors.secondaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: filteredRows.isEmpty || widget.exporting
                    ? null
                    : () => _printRows(filteredRows),
                icon: const Icon(
                  Icons.print_rounded,
                  size: 18,
                  color: AppColors.secondaryColor,
                ),
                label: const Text(
                  'Print',
                  style: TextStyle(color: AppColors.secondaryColor),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed:
                    widget.rows.isEmpty ||
                        widget.importing ||
                        widget.saving ||
                        widget.exporting
                    ? null
                    : widget.onExport,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondaryColor,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                icon: widget.exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryColor,
                        ),
                      )
                    : const Icon(
                        Icons.download_rounded,
                        size: 18,
                        color: AppColors.secondaryColor,
                      ),
                label: Text(
                  widget.exporting ? 'Exporting...' : 'Export',
                  style: const TextStyle(
                    color: AppColors.secondaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: widget.saving || widget.exporting || widget.expired
                    ? null
                    : widget.onSubmit,
                icon: widget.saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryColor,
                        ),
                      )
                    : const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                ),
                label: const Text(
                  'Submit Stock Check',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search item code or item name',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(color: Color(0xFFD9E8F5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: sourceStyle.color),
                    ),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 165,
                child: _StockCheckFilterDropdown(
                  label: 'Status',
                  icon: Icons.filter_alt_rounded,
                  value: _statusFilter,
                  color: sourceStyle.color,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'submitted',
                      child: Text('Submitted'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _statusFilter = value ?? 'all');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StockCheckMultiFilterButton(
                  label: 'Category',
                  icon: Icons.category_rounded,
                  color: sourceStyle.color,
                  allLabel: 'All categories (${categories.length})',
                  selected: _categoryFilters,
                  options: categories,
                  onTap: () => _openMultiFilter(
                    title: 'Select categories',
                    allLabel: 'All categories (${categories.length})',
                    options: categories,
                    selected: _categoryFilters,
                    onApply: (values) {
                      setState(() {
                        _categoryFilters
                          ..clear()
                          ..addAll(values);
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StockCheckMultiFilterButton(
                  label: 'Sub Category',
                  icon: Icons.account_tree_rounded,
                  color: sourceStyle.color,
                  allLabel: 'All sub categories (${subCategories.length})',
                  selected: _subCategoryFilters,
                  options: subCategories,
                  onTap: () => _openMultiFilter(
                    title: 'Select sub categories',
                    allLabel: 'All sub categories (${subCategories.length})',
                    options: subCategories,
                    selected: _subCategoryFilters,
                    onApply: (values) {
                      setState(() {
                        _subCategoryFilters
                          ..clear()
                          ..addAll(values);
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StockCheckMultiFilterButton(
                  label: 'Company',
                  icon: Icons.business_rounded,
                  color: sourceStyle.color,
                  allLabel: 'All companies (${companies.length})',
                  selected: _companyFilters,
                  options: companies,
                  onTap: () => _openMultiFilter(
                    title: 'Select companies',
                    allLabel: 'All companies (${companies.length})',
                    options: companies,
                    selected: _companyFilters,
                    onApply: (values) {
                      setState(() {
                        _companyFilters
                          ..clear()
                          ..addAll(values);
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DeadlineStatusBanner(
            expiresAt: widget.expiresAt,
            expired: widget.expired,
          ),
          const SizedBox(height: 14),
          if (widget.importing) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: widget.importProgress <= 0
                    ? null
                    : widget.importProgress.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: const Color(0xFFE0F2FE),
                color: const Color(0xFF06B6D4),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: Stack(
              children: [
                ListView.separated(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: filteredRows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final row = filteredRows[index];
                    final meta = _metaFor(row);
                    final systemController = widget.systemControllers[row.id]!;
                    final actualController = widget.actualControllers[row.id]!;
                    final editingSubmitted = _editingSubmittedIds.contains(
                      row.id,
                    );
                    final locked =
                        widget.expired ||
                        (row.isSubmitted && !editingSubmitted);
                    final autosaving = widget.autosavingIds.contains(row.id);
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: row.isSubmitted
                              ? const Color(0xFFBBF7D0)
                              : const Color(0xFFD9E8F5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .035),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: sourceStyle.background,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: sourceStyle.border),
                            ),
                            child: Icon(
                              Icons.medication_liquid_rounded,
                              color: sourceStyle.color,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  row.itemName,
                                  maxLines: 2,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _ItemCodeChip(code: row.itemCode),
                                    _SmallChip(
                                      text: widget.expired && !row.isSubmitted
                                          ? 'Expired'
                                          : row.isSubmitted
                                          ? editingSubmitted
                                                ? 'Editing'
                                                : 'Submitted'
                                          : autosaving
                                          ? 'Saving'
                                          : 'Pending',
                                    ),
                                    if (meta.category.isNotEmpty) ...[
                                      _MetaChip(
                                        icon: Icons.category_rounded,
                                        text: meta.category,
                                      ),
                                    ],
                                    if (meta.subCategory.isNotEmpty) ...[
                                      _MetaChip(
                                        icon: Icons.account_tree_rounded,
                                        text: meta.subCategory,
                                      ),
                                    ],
                                    if (meta.company.isNotEmpty) ...[
                                      _MetaChip(
                                        icon: Icons.business_rounded,
                                        text: meta.company,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                if (row.isSubmitted && !widget.expired) ...[
                                  _EditSubmittedButton(
                                    editing: editingSubmitted,
                                    prominent: true,
                                    onPressed: () {
                                      setState(() {
                                        if (editingSubmitted) {
                                          _editingSubmittedIds.remove(row.id);
                                        } else {
                                          _editingSubmittedIds.add(row.id);
                                        }
                                      });
                                      if (editingSubmitted) {
                                        widget.onRowChanged(row);
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                if (row.isSubmitted &&
                                    row.submittedByName.trim().isNotEmpty) ...[
                                  _SubmittedByChip(
                                    name: row.submittedByName,
                                    employeeId: row.submittedByEmployeeId,
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                if (row.requiresItemStatus) ...[
                                  SizedBox(
                                    width: 220,
                                    child: _RequiredItemStatusField(
                                      options: row.itemStatusOptions,
                                      value: widget.itemStatusValues[row.id],
                                      enabled: !locked,
                                      onChanged: (value) {
                                        widget.onItemStatusChanged(
                                          row.id,
                                          value,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                SizedBox(
                                  width: 150,
                                  child: _QtyField(
                                    controller: systemController,
                                    enabled: !locked,
                                    label: 'System Qty',
                                    onChanged: (_) => widget.onRowChanged(row),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 150,
                                  child: _QtyField(
                                    controller: actualController,
                                    enabled: !locked,
                                    label: 'Actual Qty',
                                    onChanged: (_) => widget.onRowChanged(row),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (showBarcodeSticker) ...[
                            const SizedBox(width: 12),
                            _BarcodeStickerCheckCell(
                              enabled:
                                  !locked && row.includeBarcodeStickerCheck,
                              value: widget.barcodeStickerValues[row.id],
                              onChanged: (value) {
                                widget.onBarcodeStickerChanged(row.id, value);
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                if (widget.importing)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Container(
                          width: 360,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 22,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFF67E8F9),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0891B2,
                                ).withValues(alpha: .22),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: _ImportingLedgerIndicator(
                            progress: widget.importProgress,
                            stage: widget.importStage,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.exporting)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .76),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(
                        child: _ExportingStockCheckIndicator(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _StockCheckItemMeta _metaFor(StockCheckTask row) {
    return widget.itemMetaByCode[_normalizeItemCode(row.itemCode)] ??
        const _StockCheckItemMeta();
  }

  List<String> _optionsFromRows(
    List<StockCheckTask> rows,
    String Function(_StockCheckItemMeta meta) select,
  ) {
    final options = rows
        .map((row) => select(_metaFor(row)).trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    options.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return options;
  }

  int _compareRows(StockCheckTask a, StockCheckTask b) {
    final keys = <String>['item_name', 'category', 'item_code'];
    for (final key in keys) {
      final cmp = _sortValue(a, key).compareTo(_sortValue(b, key));
      if (cmp != 0) return cmp;
    }
    return 0;
  }

  String _sortValue(StockCheckTask row, String key) {
    final meta = _metaFor(row);
    switch (key) {
      case 'category':
        return meta.category.toLowerCase();
      case 'sub_category':
        return meta.subCategory.toLowerCase();
      case 'company':
        return meta.company.toLowerCase();
      case 'status':
        return row.status.toLowerCase();
      case 'item_code':
        return row.itemCode.toLowerCase();
      case 'item_name':
      default:
        return row.itemName.toLowerCase();
    }
  }

  Future<void> _openMultiFilter({
    required String title,
    required String allLabel,
    required List<String> options,
    required Set<String> selected,
    required ValueChanged<Set<String>> onApply,
  }) async {
    final values = await showDialog<Set<String>>(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => _StockCheckMultiFilterDialog(
        title: title,
        allLabel: allLabel,
        options: options,
        selected: selected,
      ),
    );
    if (values == null || !mounted) return;
    onApply(values);
  }

  Future<void> _printRows(List<StockCheckTask> rows) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              widget.rows.first.title,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              widget.rows.first.branchName,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const [
              'Item Code',
              'Item Name',
              'System Qty',
              'Actual Qty',
            ],
            data: rows
                .map(
                  (row) => [
                    row.itemCode,
                    row.itemName,
                    _formatPrintQty(
                      widget.systemControllers[row.id]?.text.trim() ?? '',
                    ),
                    _formatPrintQty(
                      widget.actualControllers[row.id]?.text.trim() ?? '',
                    ),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.center,
            headerAlignment: pw.Alignment.center,
            columnWidths: {
              0: const pw.FixedColumnWidth(72),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(62),
              3: const pw.FixedColumnWidth(62),
            },
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }
}

String _formatPrintQty(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final parsed = num.tryParse(trimmed.replaceAll(',', ''));
  if (parsed == null) return trimmed;
  final fixed = parsed.toDouble().toStringAsFixed(5);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _ImportingLedgerIndicator extends StatefulWidget {
  final double progress;
  final String stage;

  const _ImportingLedgerIndicator({
    required this.progress,
    required this.stage,
  });

  @override
  State<_ImportingLedgerIndicator> createState() =>
      _ImportingLedgerIndicatorState();
}

class _ExportingStockCheckIndicator extends StatefulWidget {
  const _ExportingStockCheckIndicator();

  @override
  State<_ExportingStockCheckIndicator> createState() =>
      _ExportingStockCheckIndicatorState();
}

class _ExportingStockCheckIndicatorState
    extends State<_ExportingStockCheckIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primaryColor, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryColor.withValues(alpha: .20),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _controller,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withValues(alpha: .12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryColor.withValues(alpha: .55),
                ),
              ),
              child: const Icon(
                Icons.download_rounded,
                color: AppColors.primaryColor,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Preparing stock check export',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Building the Excel report with submitted details.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              minHeight: 6,
              backgroundColor: Color(0xFFE0F2FE),
              color: AppColors.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportingLedgerIndicatorState extends State<_ImportingLedgerIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress.clamp(0.0, 1.0);
    final percent = (progress * 100).clamp(0, 100).round();
    final stage = widget.stage.trim().isEmpty
        ? 'Processing quantities'
        : widget.stage.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotationTransition(
          turns: _controller,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F7FE),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF67E8F9), width: 1.5),
            ),
            child: const Icon(
              Icons.sync_rounded,
              color: Color(0xFF0891B2),
              size: 30,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Importing STK Ledger',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          stage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$percent%',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF0891B2),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress <= 0 ? null : progress,
            minHeight: 6,
            backgroundColor: const Color(0xFFE0F2FE),
            color: const Color(0xFF06B6D4),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Do not close this page.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DeadlineStatusBanner extends StatelessWidget {
  final DateTime? expiresAt;
  final bool expired;

  const _DeadlineStatusBanner({required this.expiresAt, required this.expired});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final remaining = expiresAt?.difference(now);
    final label = expiresAt == null
        ? 'No completion deadline'
        : expired
        ? 'Time expired - editing and submit are closed'
        : 'Time remaining: ${_formatDuration(remaining!)}';
    final dateLabel = expiresAt == null
        ? ''
        : 'Deadline ${_formatDateTime(expiresAt!)}';
    final color = expired ? const Color(0xFFDC2626) : const Color(0xFF0F766E);
    final bg = expired ? const Color(0xFFFFF1F2) : const Color(0xFFF0FDFA);
    final border = expired ? const Color(0xFFFCA5A5) : const Color(0xFF99F6E4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Icon(
              expired ? Icons.lock_clock_rounded : Icons.timer_outlined,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                if (dateLabel.isNotEmpty)
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration value) {
    final safe = value.isNegative ? Duration.zero : value;
    final days = safe.inDays;
    final hours = safe.inHours % 24;
    final minutes = safe.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _StockCheckItemMeta {
  final String category;
  final String subCategory;
  final String company;

  const _StockCheckItemMeta({
    this.category = '',
    this.subCategory = '',
    this.company = '',
  });
}

String _normalizeItemCode(String value) {
  return value.trim().toUpperCase();
}

class _StockCheckFilterDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final Color color;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _StockCheckFilterDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.color,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: Color(0xFFD9E8F5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: color),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _StockCheckMultiFilterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String allLabel;
  final Set<String> selected;
  final List<String> options;
  final VoidCallback onTap;

  const _StockCheckMultiFilterButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.allLabel,
    required this.selected,
    required this.options,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected.isNotEmpty;
    final valueText = active
        ? selected.length == 1
              ? selected.first
              : '${selected.length} selected'
        : allLabel;
    return Tooltip(
      message: active ? selected.join(', ') : allLabel,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: options.isEmpty ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: .10)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? color : const Color(0xFFD9E8F5),
              width: active ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: active ? color : const Color(0xFF475569)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? color : const Color(0xFF0F172A),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (active) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withValues(alpha: .25)),
                  ),
                  child: Text(
                    '${selected.length}',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 7),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF475569),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockCheckMultiFilterDialog extends StatefulWidget {
  final String title;
  final String allLabel;
  final List<String> options;
  final Set<String> selected;

  const _StockCheckMultiFilterDialog({
    required this.title,
    required this.allLabel,
    required this.options,
    required this.selected,
  });

  @override
  State<_StockCheckMultiFilterDialog> createState() =>
      _StockCheckMultiFilterDialogState();
}

class _StockCheckMultiFilterDialogState
    extends State<_StockCheckMultiFilterDialog> {
  late final Set<String> _selected = {...widget.selected};
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _search.trim().toLowerCase();
    final visible = widget.options.where((option) {
      return needle.isEmpty || option.toLowerCase().contains(needle);
    }).toList();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 680),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD9E8F5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.checklist_rounded,
                    color: AppColors.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _selected.isEmpty
                            ? widget.allLabel
                            : '${_selected.length} selected',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
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
              decoration: InputDecoration(
                hintText: 'Search options',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFD9E8F5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppColors.primaryColor,
                    width: 1.4,
                  ),
                ),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: visible.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Text(
                            'No matching options',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        itemBuilder: (context, index) {
                          final option = visible[index];
                          final checked = _selected.contains(option);
                          return CheckboxListTile(
                            value: checked,
                            activeColor: AppColors.primaryColor,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              option,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onChanged: (_) {
                              setState(() {
                                if (checked) {
                                  _selected.remove(option);
                                } else {
                                  _selected.add(option);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(_selected.clear),
                  child: const Text('Clear selection'),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => Navigator.pop(context, {..._selected}),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(color: Colors.white),
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

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primaryColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryColor,
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

class _ItemCodeChip extends StatelessWidget {
  final String code;

  const _ItemCodeChip({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SelectableText(
        code,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EditSubmittedButton extends StatelessWidget {
  final bool editing;
  final bool prominent;
  final VoidCallback onPressed;

  const _EditSubmittedButton({
    required this.editing,
    this.prominent = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: editing ? 'Finish editing' : 'Edit submitted values',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(prominent ? 14 : 999),
        child: Container(
          height: prominent ? 46 : 30,
          padding: EdgeInsets.symmetric(horizontal: prominent ? 14 : 10),
          decoration: BoxDecoration(
            color: editing
                ? const Color(0xFFEFF6FF)
                : prominent
                ? const Color(0xFF2563EB)
                : Colors.white,
            borderRadius: BorderRadius.circular(prominent ? 14 : 999),
            border: Border.all(
              color: editing
                  ? const Color(0xFF93C5FD)
                  : prominent
                  ? const Color(0xFF1D4ED8)
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: prominent && !editing
                ? [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: .22),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                editing ? Icons.check_rounded : Icons.edit_rounded,
                size: prominent ? 18 : 15,
                color: editing
                    ? const Color(0xFF2563EB)
                    : prominent
                    ? Colors.white
                    : const Color(0xFF64748B),
              ),
              SizedBox(width: prominent ? 7 : 5),
              Text(
                editing ? 'Done' : 'Edit',
                style: TextStyle(
                  color: editing
                      ? const Color(0xFF2563EB)
                      : prominent
                      ? Colors.white
                      : const Color(0xFF64748B),
                  fontSize: prominent ? 13 : 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QtyField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String label;
  final ValueChanged<String>? onChanged;

  const _QtyField({
    required this.controller,
    required this.enabled,
    required this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      onChanged: onChanged,
      style: const TextStyle(fontWeight: FontWeight.w900),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );
  }
}

class _RequiredItemStatusField extends StatelessWidget {
  final List<String> options;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _RequiredItemStatusField({
    required this.options,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cleanOptions = options
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final selected = cleanOptions.contains(value) ? value : null;

    return DropdownButtonFormField<String>(
      key: ValueKey('${cleanOptions.join('|')}|$selected|$enabled'),
      initialValue: selected,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      items: cleanOptions
          .map(
            (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(
                option,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          )
          .toList(growable: false),
      onChanged: enabled ? onChanged : null,
      decoration: InputDecoration(
        labelText: 'Item Status *',
        helperText: 'Required by Inventory',
        helperMaxLines: 1,
        prefixIcon: const Icon(Icons.fact_check_outlined, size: 19),
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF93C5FD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _BarcodeStickerCheckCell extends StatelessWidget {
  final bool enabled;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const _BarcodeStickerCheckCell({
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 292,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Branch Sticker is Correct',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _StickerChoice(
                label: 'Yes',
                selected: value == true,
                enabled: enabled,
                color: const Color(0xFF16A34A),
                onTap: () => onChanged(true),
              ),
              const SizedBox(width: 8),
              _StickerChoice(
                label: 'No',
                selected: value == false,
                enabled: enabled,
                color: const Color(0xFFDC2626),
                onTap: () => onChanged(false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StickerChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  const _StickerChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: .10) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Checkbox(
                value: selected,
                onChanged: enabled ? (_) => onTap() : null,
                activeColor: color,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
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

class _SmallChip extends StatelessWidget {
  final String text;

  const _SmallChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final done =
        text.toLowerCase().contains('submitted') ||
        text.toLowerCase().contains('done');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: done ? const Color(0xFFDCFCE7) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: done ? const Color(0xFF166534) : const Color(0xFF9A3412),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SubmittedByChip extends StatelessWidget {
  final String name;
  final String employeeId;

  const _SubmittedByChip({required this.name, required this.employeeId});

  @override
  Widget build(BuildContext context) {
    final id = employeeId.trim();
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primaryColor.withValues(alpha: .45),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryColor.withValues(alpha: .08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_pin_rounded,
              size: 15,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              id.isEmpty ? 'Checked by $name' : 'Checked by $name - $id',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
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
