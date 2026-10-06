import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/utils/items_tracker_excel_importer.dart';
import '../../../domain/entities/items_tracker_action_import.dart';
import '../../../domain/entities/items_tracker_record.dart';
import '../../../domain/repositories/items_tracker_repository.dart';

Future<bool> showItemsTrackerImportDialog({
  required BuildContext context,
  required ItemsTrackerRepository repository,
  required ItemsTrackerActionFile file,
  required String fileName,
  required String role,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ItemsTrackerImportDialog(
        repository: repository,
        file: file,
        fileName: fileName,
        role: role,
      ),
    ) ??
    false;

class ItemsTrackerImportDialog extends StatefulWidget {
  final ItemsTrackerRepository repository;
  final ItemsTrackerActionFile file;
  final String fileName;
  final String role;
  const ItemsTrackerImportDialog({
    super.key,
    required this.repository,
    required this.file,
    required this.fileName,
    required this.role,
  });
  @override
  State<ItemsTrackerImportDialog> createState() =>
      _ItemsTrackerImportDialogState();
}

class _ItemsTrackerImportDialogState extends State<ItemsTrackerImportDialog> {
  List<ItemsTrackerActionImportResult> _results = [];
  bool _busy = true;
  bool _finished = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = widget.file.rows.isEmpty
          ? <ItemsTrackerActionImportResult>[]
          : await widget.repository.importActions(
              widget.file.rows,
              fileName: widget.fileName,
            );
      if (mounted) {
        setState(() {
          _results = results;
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              'Could not check this file. Please recheck or try again later.';
          _busy = false;
        });
      }
    }
  }

  Future<void> _apply() async {
    final readyRows = _results
        .where((r) => r.ready)
        .map((r) => r.excelRow)
        .toSet();
    if (_busy || readyRows.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await widget.repository.importActions(
        widget.file.rows.where((r) => readyRows.contains(r.excelRow)).toList(),
        fileName: widget.fileName,
        apply: true,
      );
      if (!mounted) return;
      final replacements = {for (final r in results) r.excelRow: r};
      setState(() {
        _results = _results.map((r) => replacements[r.excelRow] ?? r).toList();
        _changed = results.any(
          (r) => r.imported || r.status == 'already_imported',
        );
        _finished = true;
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error =
              'Could not finish the import. Retry safely; actions already imported will not be repeated.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _results.where((r) => r.ready).length;
    final imported = _results.where((r) => r.imported).length;
    final skipped =
        _results.where((r) => !r.ready && !r.imported).length +
        widget.file.issues.length;
    final rowsByNumber = {for (final r in widget.file.rows) r.excelRow: r};
    final statuses = {for (final r in _results) r.excelRow: r};
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 1040,
          height: math.min(790, MediaQuery.sizeOf(context).height - 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 14, 18),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xffe6f5f5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.upload_file_outlined,
                        color: Color(0xff008a96),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _finished
                                ? 'Import results'
                                : 'Review action import',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xff19354b),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${ItemsTrackerRoles.label(widget.role)} · ${widget.fileName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xff71849a)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, _changed),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xffeef8f3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            color: Color(0xff198a68),
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Only written Action cells will be added. Blank actions, other departments and conflicting system changes are kept unchanged. Price, quantity, reason and status are reference only.',
                              style: TextStyle(
                                color: Color(0xff216644),
                                height: 1.5,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _count(
                          _finished ? '$imported imported' : '$ready ready',
                          const Color(0xff198a68),
                        ),
                        _count(
                          '${widget.file.blankRows} blank actions ignored',
                          const Color(0xff71849a),
                        ),
                        _count(
                          '$skipped skipped / need review',
                          const Color(0xffc88421),
                        ),
                      ],
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _busy && _results.isEmpty
                    ? const Center(
                        child: Text(
                          'Checking assignments and changes since export…',
                        ),
                      )
                    : widget.file.rows.isEmpty && widget.file.issues.isEmpty
                    ? const Center(
                        child: Text(
                          'No written actions found. All current system data will be kept.',
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: [
                          for (final row in rowsByNumber.values)
                            _row(row, statuses[row.excelRow]),
                          for (final issue in widget.file.issues)
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xfffff5e8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Excel row ${issue.excelRow} · ${issue.message}',
                                style: const TextStyle(
                                  color: Color(0xff9b601c),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xfff6f9fc),
                  border: Border(top: BorderSide(color: Color(0xffdee7ef))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!_finished)
                      TextButton(
                        onPressed: _busy ? null : _check,
                        child: const Text('Recheck file'),
                      ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, _changed),
                      child: Text(_finished ? 'Close' : 'Cancel'),
                    ),
                    const SizedBox(width: 12),
                    if (!_finished)
                      FilledButton.icon(
                        key: const ValueKey('itemsTrackerConfirmImport'),
                        onPressed: _busy || ready == 0 || _error != null
                            ? null
                            : _apply,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff008a96),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        icon: const Icon(Icons.file_upload_outlined, size: 18),
                        label: Text('Import $ready actions'),
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

  Widget _count(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
    ),
  );

  Widget _row(
    ItemsTrackerActionImport row,
    ItemsTrackerActionImportResult? result,
  ) {
    final ok = result?.ready == true || result?.imported == true;
    final color = ok ? const Color(0xff198a68) : const Color(0xffc88421);
    final label = switch (result?.status) {
      'ready' => 'Ready',
      'imported' => 'Imported',
      'already_imported' => 'Already imported',
      'conflict' => 'System changed',
      'not_assigned' => 'Different department',
      'missing' => 'Product missing',
      _ => 'Needs review',
    };
    return Container(
      key: ValueKey('importRow:${row.excelRow}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffdee7ef)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.itemName.isEmpty ? row.itemCode : row.itemName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xff19354b),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _count(label, color),
            ],
          ),
          Text(
            'Excel row ${row.excelRow} · ${row.itemCode}',
            style: const TextStyle(fontSize: 11, color: Color(0xff71849a)),
          ),
          const SizedBox(height: 10),
          Text(
            row.body,
            style: const TextStyle(color: Color(0xff19354b), height: 1.5),
          ),
          if (!ok && result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                result.message,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
