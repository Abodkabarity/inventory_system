import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/print_additional_service.dart';
import '../../../data/repositories/store_additional_request_repository.dart';
import '../../../domain/entities/store_additional_request_status.dart';
import 'store_branch_identity.dart';

typedef AdditionalRequestPrinter =
    Future<bool> Function(Map<String, List<Map<String, dynamic>>> batch);

class AdditionalRequestDialog extends StatefulWidget {
  final String groupId, branch, sourceTable;
  final SupabaseClient? client;
  final AdditionalRequestPrinter? printer;

  const AdditionalRequestDialog({
    super.key,
    required this.groupId,
    required this.branch,
    this.sourceTable = 'additional_requests',
    this.client,
    this.printer,
  });

  @override
  State<AdditionalRequestDialog> createState() =>
      _AdditionalRequestDialogState();
}

class _AdditionalRequestDialogState extends State<AdditionalRequestDialog> {
  late final _repository = StoreAdditionalRequestRepository(
    widget.client ?? Supabase.instance.client,
    groupId: widget.groupId,
    branch: widget.branch,
    sourceTable: widget.sourceTable,
  );
  List<Map<String, dynamic>> _items = [];
  bool _loading = true, _printing = false, _changed = false;
  String? _error, _message;
  StoreAdditionalRequestStatus get _status =>
      StoreAdditionalRequestStatus(_items);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      final rows = await _repository.load();
      if (mounted) setState(() => _items = rows);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load this request. Please refresh.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _print() async {
    if (_printing || _loading) return;
    setState(() {
      _printing = true;
      _error = null;
      _message = null;
    });
    var printAccepted = false;
    try {
      // Another Store user may have confirmed lines while this dialog was open.
      final fresh = await _repository.load();
      if (!mounted) return;
      setState(() => _items = fresh);
      final status = StoreAdditionalRequestStatus(fresh);
      final printable = status.printable;
      if (printable.isEmpty) {
        setState(
          () => _message =
              'No pending items to print. The request has been refreshed.',
        );
        return;
      }
      final batch = <String, List<Map<String, dynamic>>>{};
      for (final item in printable) {
        final branch = (item['branch_name'] ?? widget.branch).toString();
        batch
            .putIfAbsent(branch, () => [])
            .add(Map<String, dynamic>.from(item));
      }
      printAccepted =
          await (widget.printer ?? PrintAdditionalService.printBatch)(batch);
      if (!printAccepted) {
        if (mounted) {
          setState(
            () => _message =
                'Printing cancelled. Request status was not changed.',
          );
        }
        return;
      }
      // Reprints of processing lines are read-only. Only the exact pending
      // lines sent to the printer can transition; completed lines never do.
      final changed = await _repository.markPrinted(printable);
      _changed = _changed || changed > 0;
      final refreshed = await _repository.load();
      if (!mounted) return;
      setState(() {
        _items = refreshed;
        _message =
            changed <
                printable.where(StoreAdditionalRequestStatus.waiting).length
            ? 'Printing opened. Some items changed during printing; the request has been refreshed.'
            : 'Printing opened. Confirm sent Qty in Additional Confirm.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = printAccepted
            ? 'Printing opened, but its status could not be verified. Refresh before retrying.'
            : 'Could not print this request. Please refresh and try again.',
      );
      // A failed write may have committed. Never replay it automatically.
      if (printAccepted) {
        _changed = true;
        try {
          final refreshed = await _repository.load();
          if (mounted) setState(() => _items = refreshed);
        } catch (_) {
          /* Keep the error visible and require an explicit refresh. */
        }
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final rows = [...status.items]
      ..sort(
        (a, b) => (a['item_name'] ?? '').toString().compareTo(
          (b['item_name'] ?? '').toString(),
        ),
      );
    return PopScope(
      canPop: !_printing,
      child: Dialog(
        backgroundColor: Colors.grey.shade100,
        child: SizedBox(
          width: 950,
          height: 620,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: widget.sourceTable == 'additional_order_inventory'
                          ? const Text(
                              'Additional Order - From Inventory',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : StoreBranchLabel(
                              branchName: widget.branch,
                              suffix: 'Additional Order',
                              compactBadge: false,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      color: Colors.black,
                      onPressed: _printing
                          ? null
                          : () => Navigator.pop(context, _changed),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(color: AppColors.primaryColor),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryColor,
                          ),
                        )
                      : rows.isEmpty
                      ? const Center(child: Text('No approved items'))
                      : ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (_, index) => _item(rows[index]),
                        ),
                ),
                const SizedBox(height: 10),
                if (!_loading &&
                    (status.complete ||
                        (status.pending.isEmpty && status.printed.isNotEmpty)))
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: status.allRejected
                          ? Colors.red.shade100
                          : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          status.allRejected
                              ? Icons.cancel
                              : Icons.check_circle,
                          color: status.allRejected ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            status.complete ? status.label : 'Already printed',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null || _message != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error ?? _message!,
                      style: TextStyle(
                        color: _error == null
                            ? AppColors.secondaryColor
                            : Colors.red.shade800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (_error != null || _message != null)
                        TextButton.icon(
                          onPressed: _loading || _printing ? null : _load,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      if (!_loading && status.printable.isNotEmpty)
                        ElevatedButton.icon(
                          onPressed: _printing || _error != null
                              ? null
                              : _print,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          icon: _printing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.print),
                          label: Text(
                            _printing
                                ? 'Printing...'
                                : status.pending.isNotEmpty
                                ? 'Print pending (${status.printable.length})'
                                : 'Reprint processing (${status.printable.length})',
                          ),
                        )
                      else
                        ElevatedButton(
                          onPressed: _printing
                              ? null
                              : () => Navigator.pop(context, _changed),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Close'),
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
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.backgroundWidget,
    labelStyle: const TextStyle(color: AppColors.secondaryColor),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.primaryColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.primaryColor),
    ),
  );

  Widget _item(Map<String, dynamic> item) {
    final finished = StoreAdditionalRequestStatus.finished(item);
    final (
      statusLabel,
      statusColor,
    ) = switch (StoreAdditionalRequestStatus.status(item)) {
      'done' => ('Done', Colors.green.shade700),
      'rejected' => ('Rejected', Colors.red.shade700),
      'sent_to_store' when StoreAdditionalRequestStatus.processing(item) => (
        'Processing',
        AppColors.primaryColor,
      ),
      'sent_to_store' => ('Pending', Colors.orange.shade800),
      _ => ('Awaiting review', AppColors.subText),
    };
    final qty = finished
        ? item['fulfilled_qty'] ?? 0
        : item['inventory_qty'] ?? item['request_qty'] ?? 0;
    final note = (item['store_note'] ?? '').toString();
    final requested = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Requested: '),
        Text(
          '${item['inventory_qty'] ?? item['request_qty'] ?? 0}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red,
            fontSize: 15,
          ),
        ),
      ],
    );
    final qtyField = SizedBox(
      width: 120,
      child: TextFormField(
        key: ValueKey('additional-qty-${item['id']}-$qty'),
        initialValue: qty.toString(),
        readOnly: true,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.secondaryColor,
        ),
        decoration: _fieldDecoration('Sent Qty'),
      ),
    );
    final noteField = TextFormField(
      key: ValueKey('additional-note-${item['id']}-$note'),
      initialValue: note,
      readOnly: true,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: AppColors.secondaryColor,
      ),
      decoration: _fieldDecoration('Store Note'),
    );
    return Card(
      key: ValueKey('additional-item-${item['id']}'),
      color: Colors.white,
      shadowColor: AppColors.primaryColor,
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${item['item_code'] ?? ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                if (item['contact_logistic'] == 'urgent') ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'URGENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${item['item_name'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            if (widget.sourceTable == 'additional_order_inventory') ...[
              Row(
                children: [
                  const Text(
                    'Branch: ',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Expanded(
                    child: StoreBranchLabel(
                      branchName: '${item['branch_name'] ?? ''}',
                      compactBadge: false,
                      style: const TextStyle(
                        color: AppColors.secondaryColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 620
                  ? Row(
                      children: [
                        requested,
                        const SizedBox(width: 20),
                        qtyField,
                        const SizedBox(width: 20),
                        Expanded(child: noteField),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            requested,
                            const SizedBox(width: 12),
                            Expanded(child: qtyField),
                          ],
                        ),
                        const SizedBox(height: 12),
                        noteField,
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
